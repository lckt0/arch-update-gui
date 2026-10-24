#!/usr/bin/env python3
# arch-update / cachy-update icin tepsi acilir penceresi.
#
# - Guncellenecek paketler (depo / AUR / Flatpak), Arch haberleri ve Guncelle dugmesi.
# - Yalnizca elle mudahale gerektirebilecek durumda soru sorar: yeni Arch haberi,
#   pacman kuru denemesinde hata/soru, depoda ilerlemis bir paketin yerine gecen yerel
#   paket (ornegin elle derlenmis bir -git paketi). Aksi halde dugmeye basinca guncelleme hemen baslar.
# - Guncelleme runner.sh ile ayri bir systemd kullanici biriminde yurur; pencere
#   kapansa da surer. Pencere yeniden acilinca run.log'dan ilerlemeyi okur.

import email.utils
import html
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

from PySide6.QtCore import Property, QObject, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QDesktopServices, QGuiApplication
from PySide6.QtNetwork import QLocalServer, QLocalSocket
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtWidgets import QApplication

HERE = Path(__file__).resolve().parent
HOME = Path.home()
STATE = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state"))
AU_STATE = STATE / "arch-update"
GUI_STATE = STATE / "arch-update-gui"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", tempfile.gettempdir()))
RUN_LOG = GUI_STATE / "run.log"
RUN_RESULT = GUI_STATE / "run.result"
ACKS = GUI_STATE / "acks.json"
UNIT = "arch-update-gui-run"
SOCKET_NAME = f"arch-update-gui-{os.getuid()}"
CLOSED_STAMP = RUNTIME / "arch-update-gui.closed"
NEWS_URL = "https://archlinux.org/feeds/news/"
NEWS_NUM = 6
DEMO = os.environ.get("ARCH_UPDATE_GUI_DEMO") == "1"

ANSI_RE = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b[()][0-9A-Za-z]|\x1b[=>]|\x00")
UPD_RE = re.compile(r"^(\S+)\s+(\S+)\s+->\s+(\S+)")
COUNT_RE = re.compile(r"\(\s*(\d+)/(\d+)\)")
TOTAL_RE = re.compile(r"Total\s*\(\s*(\d+)/(\d+)\)")
ACTION_RE = re.compile(r"^\(\s*\d+/\d+\)\s+(upgrading|installing|reinstalling|removing|downgrading)\s+(\S+)")


def run(cmd, timeout=120, env=None, **kw):
    e = dict(os.environ, LC_ALL="C.UTF-8", LANG="C.UTF-8")
    if env:
        e.update(env)
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                           stdin=subprocess.DEVNULL, env=e, **kw)
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return 124, "", "zaman aşımı"
    except FileNotFoundError:
        return 127, "", f"{cmd[0]} bulunamadı"


def load_json(path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def save_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1))
    tmp.replace(path)


def read_text(path):
    try:
        return path.read_text()
    except OSError:
        return ""


def tray_style():
    conf = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "arch-update/arch-update.conf"
    m = re.search(r"^\s*TrayIconStyle\s*=\s*(blue|light|dark)\s*$", read_text(conf), re.M)
    return m.group(1) if m else "blue"


def human_ago(ts):
    d = int(time.time() - ts)
    if d < 60:
        return "az önce"
    if d < 3600:
        return f"{d // 60} dk önce"
    if d < 86400:
        return f"{d // 3600} sa önce"
    return f"{d // 86400} gün önce"


def split_version(old, new):
    """Ortak oneki ayir: degisen kismi vurgulamak icin (arch-update'in renklendirmesi gibi)."""
    i = 0
    n = min(len(old), len(new))
    while i < n and old[i] == new[i]:
        i += 1
    # bir segment sinirina geri cek (. - : +)
    while i > 0 and old[i - 1] not in ".-:+_":
        i -= 1
    return old[:i], old[i:], new[i:]


class Backend(QObject):
    changed = Signal()
    logChanged = Signal()
    showRequested = Signal()
    _checkDone = Signal(dict)
    _newsDone = Signal(dict)

    def __init__(self):
        super().__init__()
        self._mode = "checking"  # checking | ready | confirm | updating | done
        self._packages = []
        self._news = []
        self._newsError = ""
        self._warnings = []
        self._notes = []
        self._checkError = ""
        self._checking = False
        self._newsLoading = False
        self._lastCheck = ""
        self._log_lines = []
        self._log_partial = ""
        self._log_pos = 0
        self._step = ""
        self._stepLabel = ""
        self._progress = -1.0
        self._phase = ""
        self._result = {}
        self._acks = load_json(ACKS, {})
        self._checkDone.connect(self._on_check_done)
        self._newsDone.connect(self._on_news_done)
        self._tail = QTimer(self)
        self._tail.setInterval(250)
        self._tail.timeout.connect(self._poll_log)

        self._load_cached()
        if self._unit_active():
            self._enter_updating(resume=True)
        elif RUN_RESULT.exists() and not self._acks.get("result_seen"):
            self._read_result()
            self._mode = "done"
            self._read_log_all()
        else:
            self.refresh()
        self.fetchNews()

    # ---------------- ozellikler ----------------
    def _p(name, typ="QVariant", notify=changed):
        return Property(typ, lambda self: getattr(self, "_" + name), notify=notify)

    mode = _p("mode", str)
    packages = _p("packages", "QVariantList")
    news = _p("news", "QVariantList")
    newsError = _p("newsError", str)
    warnings = _p("warnings", "QVariantList")
    notes = _p("notes", "QVariantList")
    checkError = _p("checkError", str)
    checking = _p("checking", bool)
    newsLoading = _p("newsLoading", bool)
    lastCheck = _p("lastCheck", str)
    stepLabel = _p("stepLabel", str)
    step = _p("step", str)
    progress = _p("progress", float)
    result = _p("result", "QVariantMap")
    del _p

    @Property(str, notify=logChanged)
    def log(self):
        lines = self._log_lines[-400:]
        if self._log_partial:
            lines = lines + [self._log_partial]
        return "\n".join(lines)

    @Property(int, notify=changed)
    def repoCount(self):
        return sum(1 for p in self._packages if p["source"] == "repo")

    @Property(int, notify=changed)
    def aurCount(self):
        return sum(1 for p in self._packages if p["source"] == "aur")

    @Property(int, notify=changed)
    def flatpakCount(self):
        return sum(1 for p in self._packages if p["source"] == "flatpak")

    @Property(int, notify=changed)
    def blockingCount(self):
        return sum(1 for w in self._warnings if w.get("blocking"))

    # ---------------- yardimcilar ----------------
    def _set(self, **kw):
        for k, v in kw.items():
            setattr(self, "_" + k, v)
        self.changed.emit()

    def _unit_active(self):
        rc, out, _ = run(["systemctl", "--user", "is-active", UNIT], timeout=5)
        return out.strip() in ("active", "activating")

    def _load_cached(self):
        """Pencere aninda dolsun diye arch-update'in son kontrol sonuclarini goster."""
        pk = []
        for line in read_text(AU_STATE / "last_updates_check_packages").splitlines():
            m = UPD_RE.match(line)
            if m:
                pk.append(self._pkg(m.group(1), m.group(2), m.group(3), "repo"))
        for line in read_text(AU_STATE / "last_updates_check_aur").splitlines():
            m = UPD_RE.match(line)
            if m:
                pk.append(self._pkg(m.group(1), m.group(2), m.group(3), "aur"))
        for line in read_text(AU_STATE / "last_updates_check_flatpak").splitlines():
            if line.strip():
                parts = line.rsplit(" ", 1)
                pk.append(self._pkg(parts[0], "", parts[1] if len(parts) > 1 else "", "flatpak"))
        self._packages = pk
        t = read_text(AU_STATE / "last_updates_check_time").splitlines()
        if t and t[0].isdigit():
            self._lastCheck = human_ago(int(t[0]))

    @staticmethod
    def _pkg(name, old, new, source):
        common, oldTail, newTail = split_version(old, new) if old else ("", "", new)
        return {"name": name, "old": old, "new": new, "source": source,
                "common": common, "oldTail": oldTail, "newTail": newTail}

    # ---------------- kontrol ----------------
    @Slot()
    def refresh(self):
        if self._checking or self._mode == "updating":
            return
        self._set(checking=True, checkError="",
                  mode="checking" if not self._packages else self._mode if self._mode != "done" else "ready")
        threading.Thread(target=self._check_worker, daemon=True).start()

    def _check_worker(self):
        try:
            res = demo_check() if DEMO else self._do_check()
        except Exception as ex:  # noqa: BLE001
            res = {"error": f"Kontrol başarısız: {ex}"}
        self._checkDone.emit(res)

    def _do_check(self):
        res = {"packages": [], "warnings": [], "notes": [], "error": ""}
        dbdir = Path(tempfile.mkdtemp(prefix="arch-update-gui-db.", dir=RUNTIME))
        try:
            # 1) Depo: checkupdates, ayri bir senkron veritabaniyla (sistem db'sine dokunmaz)
            rc, out, err = run(["checkupdates", "--nocolor"], timeout=180,
                               env={"CHECKUPDATES_DB": str(dbdir)})
            repo_lines = []
            if rc == 0:
                for line in out.splitlines():
                    m = UPD_RE.match(line)
                    if m:
                        repo_lines.append(line.strip())
                        res["packages"].append(self._pkg(m.group(1), m.group(2), m.group(3), "repo"))
            elif rc != 2:
                res["error"] = "Depo güncellemeleri alınamadı: " + (err.strip().splitlines() or ["zaman aşımı"])[-1]

            # 2) Kuru deneme: pacman -Syu gercekte soru soracak ya da hata verecek mi?
            if repo_lines:
                rc, out, err = run(["pacman", "-Sup", "--dbpath", str(dbdir), "--logfile", "/dev/null",
                                    "--noconfirm", "--print-format", "%n %v"], timeout=120)
                questions = [l.strip() for l in (out + "\n" + err).splitlines()
                             if l.startswith("::") and "Synchronizing" not in l and "Starting full system upgrade" not in l]
                errors = [l.strip() for l in err.splitlines() if l.startswith("error:") or l.startswith(":: ") and "conflict" in l]
                if rc != 0:
                    res["warnings"].append({
                        "id": "", "kind": "pacman", "blocking": True,
                        "title": "pacman kuru denemesi başarısız — güncelleme kendiliğinden tamamlanamaz",
                        "detail": "\n".join(errors or err.strip().splitlines()[-6:])})
                elif questions:
                    res["warnings"].append({
                        "id": "", "kind": "pacman", "blocking": True,
                        "title": "pacman güncelleme sırasında soru soracak",
                        "detail": "\n".join(dict.fromkeys(questions))})
                for l in err.splitlines():
                    if l.startswith("warning:") and "is newer than" not in l:
                        res["notes"].append(l[len("warning:"):].strip())

            # 3) Depodaki bir paketin yerine gecen yerel paket geride kaldi mi?
            res["warnings"] += self._local_substitutes(dbdir)
        finally:
            shutil.rmtree(dbdir, ignore_errors=True)

        # 4) AUR
        aur_lines = []
        if shutil.which("yay"):
            rc, out, err = run(["yay", "-Qua", "--color", "never"], timeout=180)
            for line in out.splitlines():
                line = line.strip()
                if "[ignored]" in line:
                    continue
                m = UPD_RE.match(line)
                if m:
                    aur_lines.append(line)
                    res["packages"].append(self._pkg(m.group(1), m.group(2), m.group(3), "aur"))

        # 5) Flatpak
        fp_lines = []
        if shutil.which("flatpak"):
            rc, out, _ = run(["flatpak", "remote-ls", "--updates", "--columns=application,name,version"], timeout=120)
            if rc == 0 and out.strip():
                _, inst, _ = run(["flatpak", "list", "--columns=application,version"], timeout=30)
                cur = dict(l.split("\t", 1) for l in inst.splitlines() if "\t" in l)
                for line in out.splitlines():
                    cols = line.split("\t")
                    if len(cols) < 2:
                        continue
                    app, name = cols[0], cols[1]
                    ver = cols[2] if len(cols) > 2 else ""
                    fp_lines.append(f"{name} {ver}".strip())
                    res["packages"].append(self._pkg(name, cur.get(app, ""), ver, "flatpak"))

        # arch-update'in durum dosyalarini da guncelle — tepsi simgesi ayni bilgiyi gostersin
        try:
            AU_STATE.mkdir(parents=True, exist_ok=True)
            (AU_STATE / "last_updates_check_packages").write_text("".join(l + "\n" for l in repo_lines))
            (AU_STATE / "last_updates_check_aur").write_text("".join(l + "\n" for l in aur_lines))
            (AU_STATE / "last_updates_check_flatpak").write_text("".join(l + "\n" for l in fp_lines))
            (AU_STATE / "last_updates_check").write_text("".join(l + "\n" for l in repo_lines + aur_lines + fp_lines))
            (AU_STATE / "last_updates_check_time").write_text(time.strftime("%s\n%F %T\n"))
            style = tray_style()
            icon = f"cachy-update_updates-available-{style}" if res["packages"] else f"cachy-update-{style}"
            (AU_STATE / "tray_icon").write_text(icon + "\n")
        except OSError:
            pass
        return res

    @staticmethod
    def _local_substitutes(dbdir):
        out = []
        rc, qi, _ = run(["pacman", "-Qmi"], timeout=30)
        for block in qi.split("\n\n"):
            f = {}
            key = None
            for line in block.splitlines():
                if " : " in line and not line.startswith(" "):
                    key, val = line.split(" : ", 1)
                    key = key.strip()
                    f[key] = val.strip()
                elif key:
                    f[key] += " " + line.strip()
            name = f.get("Name")
            if not name:
                continue
            conflicts = set(f.get("Conflicts With", "None").split())
            for prov in f.get("Provides", "None").split():
                if "=" not in prov:
                    continue
                pname, pver = prov.split("=", 1)
                if pname not in conflicts:
                    continue
                rc, si, _ = run(["pacman", "-Si", "--dbpath", str(dbdir), pname], timeout=30)
                m = re.search(r"^Version\s*:\s*(\S+)", si, re.M)
                if rc != 0 or not m:
                    continue
                repo_ver = m.group(1)
                repo_up = repo_ver.rsplit("-", 1)[0]
                rc, cmp_out, _ = run(["vercmp", pver.rsplit("-", 1)[0], repo_up], timeout=5)
                if cmp_out.strip().lstrip("-").isdigit() and int(cmp_out) < 0:
                    out.append({
                        "id": f"local:{name}:{pname}:{repo_ver}", "kind": "local", "blocking": False,
                        "title": f"{name} depodaki {pname} sürümünün gerisinde kaldı",
                        "detail": f"Kurulu yerel paket {pname} {pver} sağlıyor, depoda {repo_ver} var. "
                                  f"Yeniden derlenmesi gerekebilir; ona bağlı paketler uyumsuz kalabilir."})
        return out

    @Slot(dict)
    def _on_check_done(self, res):
        if res.get("error") and not res.get("packages") and "packages" not in res:
            self._set(checking=False, checkError=res["error"], mode="ready" if self._mode == "checking" else self._mode)
            return
        self._packages = res.get("packages", [])
        self._checkError = res.get("error", "")
        self._base_warnings = res.get("warnings", [])
        self._notes = res.get("notes", [])
        self._lastCheck = "az önce"
        self._checking = False
        self._rebuild_warnings()
        if self._mode in ("checking",):
            self._mode = "ready"
        self.changed.emit()

    def _rebuild_warnings(self):
        acked = set(self._acks.get("ids", []))
        ws = [w for w in getattr(self, "_base_warnings", []) if not w["id"] or w["id"] not in acked]
        for n in self._news:
            if n["isNew"]:
                ws.append({"id": n["id"], "kind": "news", "blocking": False,
                           "title": f"Yeni Arch haberi: {n['title']}", "detail": n["date"], "newsIndex": n["index"]})
        self._warnings = ws

    # ---------------- haberler ----------------
    @Slot()
    def fetchNews(self):
        if self._newsLoading:
            return
        self._set(newsLoading=True)
        threading.Thread(target=self._news_worker, daemon=True).start()

    def _news_worker(self):
        try:
            if DEMO:
                data = demo_news_xml()
            else:
                req = urllib.request.Request(NEWS_URL, headers={"User-Agent": "arch-update-gui"})
                with urllib.request.urlopen(req, timeout=15) as r:
                    data = r.read()
            root = ET.fromstring(data)
            items = []
            for it in list(root.iter("item"))[:NEWS_NUM]:
                title = it.findtext("title", "")
                link = it.findtext("link", "")
                desc = it.findtext("description", "")
                pub = email.utils.parsedate_to_datetime(it.findtext("pubDate", ""))
                items.append({"title": title, "link": link, "html": desc,
                              "ts": pub.timestamp(), "id": "news:" + (it.findtext("guid") or link)})
            self._newsDone.emit({"items": items})
        except Exception as ex:  # noqa: BLE001
            self._newsDone.emit({"error": f"Arch haberleri alınamadı ({ex.__class__.__name__}) — archlinux.org'a elle bakın"})

    @Slot(dict)
    def _on_news_done(self, res):
        if "error" in res:
            self._set(newsLoading=False, newsError=res["error"])
            return
        items = res["items"]
        acked = set(self._acks.get("ids", []))
        if "news_baseline" not in self._acks:
            # Ilk calisma: arch-update'in en son gosterdigi haber ve ondan eskiler okunmus sayilir
            last_title = read_text(AU_STATE / "last_news_check").strip()
            seen = False
            for it in items:
                if it["title"] == last_title:
                    seen = True
                if seen:
                    acked.add(it["id"])
            if not seen:
                lur = read_text(AU_STATE / "last_update_run").strip()
                try:
                    base = datetime.strptime(lur, "%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp()
                except ValueError:
                    base = time.time() - 14 * 86400  # bilgi yoksa: iki haftadan eskiler okunmus say
                acked |= {it["id"] for it in items if it["ts"] < base}
            self._acks["ids"] = sorted(acked)
            self._acks["news_baseline"] = True
            save_json(ACKS, self._acks)
        news = []
        for i, it in enumerate(items):
            news.append({"index": i, "id": it["id"], "title": it["title"], "link": it["link"],
                         "date": datetime.fromtimestamp(it["ts"]).strftime("%d.%m.%Y"),
                         "html": it["html"], "isNew": it["id"] not in acked})
        self._news = news
        self._newsError = ""
        self._newsLoading = False
        self._rebuild_warnings()
        self.changed.emit()

    # ---------------- guncelleme ----------------
    @Slot()
    def requestUpdate(self):
        """Guncelle dugmesi: elle mudahale gerektiren bir sey yoksa hemen basla."""
        if not self._packages or self._mode == "updating":
            return
        if self._warnings:
            self._set(mode="confirm")
        else:
            self.startUpdate()

    @Slot()
    def cancelConfirm(self):
        self._set(mode="ready")

    def _ack_all(self):
        ids = set(self._acks.get("ids", []))
        ids |= {w["id"] for w in self._warnings if w["id"]}
        ids |= {n["id"] for n in self._news}
        self._acks["ids"] = sorted(ids)
        save_json(ACKS, self._acks)

    @Slot()
    def startUpdate(self):
        if self._unit_active():
            # zaten bir guncelleme suruyor (baska pencereden baslatilmis) — ona baglan
            self._enter_updating()
            return
        self._ack_all()
        self._acks["result_seen"] = False
        save_json(ACKS, self._acks)
        args = []
        if self.repoCount:
            args.append("--repo")
        if self.aurCount:
            args.append("--aur")
        if self.flatpakCount:
            args.append("--flatpak")
        GUI_STATE.mkdir(parents=True, exist_ok=True)
        RUN_LOG.write_text("")
        RUN_RESULT.unlink(missing_ok=True)
        cmd = ["systemd-run", "--user", f"--unit={UNIT}", "--collect", "--quiet",
               "--description=Arch güncellemesi (arch-update-gui)"]
        for var in ("XDG_STATE_HOME", "XDG_CONFIG_HOME", "DEMO_DELAY", "DEMO_RC", "DEMO_MSG"):
            if os.environ.get(var):
                cmd.append(f"--setenv={var}={os.environ[var]}")
        cmd += [str(HERE / ("demo-runner.sh" if DEMO else "runner.sh"))] + args
        rc, _, err = run(cmd, timeout=15)
        if rc != 0:
            self._set(checkError="Güncelleme başlatılamadı: " + err.strip(), mode="ready")
            return
        self._enter_updating()

    @Slot()
    def updateInTerminal(self):
        """Elle mudahale gerektiren durumda tam etkilesimli arch-update'i terminalde ac."""
        self._ack_all()
        subprocess.Popen(["konsole", "-e", "arch-update"], start_new_session=True,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        QApplication.quit()

    def _enter_updating(self, resume=False):
        self._log_lines = []
        self._log_partial = ""
        self._log_pos = 0
        self._step = ""
        self._phase = ""
        self._progress = -1.0
        self._stepLabel = "Başlatılıyor…"
        self._mode = "updating"
        self.changed.emit()
        self.logChanged.emit()
        self._tail.start()

    def _read_log_all(self):
        self._log_lines, self._log_partial, self._log_pos = [], "", 0
        self._poll_log(final=True)

    def _poll_log(self, final=False):
        try:
            with open(RUN_LOG, "rb") as f:
                f.seek(self._log_pos)
                chunk = f.read()
                self._log_pos = f.tell()
        except OSError:
            chunk = b""
        ended = None
        if chunk:
            text = ANSI_RE.sub("", chunk.decode("utf-8", "replace"))
            for ch in re.split(r"(\r\n|\n|\r)", text):
                if ch in ("\n", "\r\n"):
                    ended = self._commit_line(self._log_partial) or ended
                    self._log_partial = ""
                elif ch == "\r":
                    # ilerleme cubugu satiri yeniden ciziyor
                    self._progress_from(self._log_partial)
                    self._log_partial = ""
                else:
                    self._log_partial += ch
            if self._log_partial:
                self._progress_from(self._log_partial)
            if len(self._log_lines) > 3000:
                self._log_lines = self._log_lines[-2000:]
            self.logChanged.emit()
            self.changed.emit()
        if final:
            return
        if ended is not None or (not chunk and not self._unit_active() and RUN_RESULT.exists()):
            self._tail.stop()
            self._read_result()
            self._set(mode="done")
        elif not chunk and not self._unit_active() and not RUN_RESULT.exists():
            # birim sonuc yazmadan bitti (oldu/cokturuldu)
            self._tail.stop()
            self._result = {"rc": "99", "msg": "Güncelleme birimi beklenmedik biçimde sonlandı — günlüğe bakın"}
            self._set(mode="done")

    def _commit_line(self, line):
        line = line.rstrip()
        if line.startswith("@@STEP "):
            step = line.split()[1]
            labels = {"repo": "Depo paketleri", "aur": "AUR paketleri", "flatpak": "Flatpak paketleri",
                      "post": "Son işlemler"}
            self._step = step
            self._phase = ""
            self._stepLabel = labels.get(step, step) + "…"
            self._progress = -1.0
            return None
        if line.startswith("@@END"):
            return True
        if line.startswith("@@"):
            return None
        if line or (self._log_lines and self._log_lines[-1]):
            self._log_lines.append(line)
        self._progress_from(line)
        return None

    def _progress_from(self, line):
        line = line.strip()
        if not line:
            return
        if self._step == "repo":
            if line.startswith(":: Retrieving packages"):
                self._phase = "dl"
                self._stepLabel = "Paketler indiriliyor…"
            elif line.startswith(":: Processing package changes"):
                self._phase = "inst"
                self._stepLabel = "Paketler kuruluyor…"
            elif line.startswith(":: Running post-transaction hooks"):
                self._phase = "hooks"
                self._stepLabel = "Kancalar çalışıyor…"
            elif line.startswith(":: Synchronizing"):
                self._stepLabel = "Depolar eşitleniyor…"
                self._progress = 0.02
            m = TOTAL_RE.search(line)
            if m and self._phase == "dl":
                a, b = int(m.group(1)), int(m.group(2))
                self._progress = 0.03 + 0.37 * a / max(b, 1)
                self._stepLabel = f"Paketler indiriliyor ({a}/{b})"
                return
            m = COUNT_RE.match(line)
            if m:
                a, b = int(m.group(1)), int(m.group(2))
                if self._phase == "inst":
                    am = ACTION_RE.match(line)
                    self._progress = 0.45 + 0.45 * a / max(b, 1)
                    self._stepLabel = f"Kuruluyor ({a}/{b})" + (f": {am.group(2)}" if am else "")
                elif self._phase == "hooks":
                    self._progress = 0.9 + 0.1 * a / max(b, 1)
                    self._stepLabel = f"Kancalar çalışıyor ({a}/{b})"
                elif self._phase == "dl" or "checking" in line or "loading" in line:
                    self._phase = "verify"
                    self._progress = 0.40 + 0.05 * a / max(b, 1)
                    self._stepLabel = "Paketler doğrulanıyor…"
        elif self._step == "aur":
            m = re.match(r"^==> Making package: (\S+)", line)
            if m:
                self._stepLabel = f"AUR derleniyor: {m.group(1)}"
            m = COUNT_RE.match(line)
            if m and ACTION_RE.match(line):
                self._stepLabel = f"AUR kuruluyor: {ACTION_RE.match(line).group(2)}"
        elif self._step == "flatpak":
            m = re.match(r"^\s*(\d+)\.\s+\S+\s+(\S+)", line)
            if m:
                self._stepLabel = f"Flatpak: {m.group(2)}"
        elif self._step == "post":
            self._stepLabel = "Önbellek temizleniyor, kontroller yapılıyor…"

    def _read_result(self):
        r = {}
        for line in read_text(RUN_RESULT).splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                r[k] = v
        r.setdefault("rc", "99")
        self._result = r

    @Slot()
    def dismissResult(self):
        self._acks["result_seen"] = True
        save_json(ACKS, self._acks)
        self._result = {}
        self._mode = "checking"
        self._packages = []
        self.changed.emit()
        self.refresh()

    @Slot()
    def markResultSeen(self):
        if self._mode == "done":
            self._acks["result_seen"] = True
            save_json(ACKS, self._acks)

    @Slot()
    def reboot(self):
        subprocess.Popen(["qdbus6", "org.kde.LogoutPrompt", "/LogoutPrompt", "promptReboot"],
                         start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    @Slot()
    def openLog(self):
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(RUN_LOG)))

    @Slot(str)
    def openUrl(self, url):
        QDesktopServices.openUrl(QUrl(url))


# ---------------- deneme verisi (ARCH_UPDATE_GUI_DEMO=1) ----------------
def demo_check():
    time.sleep(0.6)
    P = Backend._pkg
    pk = [P("linux-firmware", "20260901.abcd-1", "20260928.ef01-1", "repo"),
          P("mesa", "1:26.2.3-1", "1:26.2.4-1", "repo"),
          P("plasma-workspace", "6.7.5-1", "6.7.6-1", "repo"),
          P("kwin", "6.7.5-1", "6.7.6-1", "repo"),
          P("firefox", "143.0.1-1", "143.0.3-1", "repo"),
          P("systemd", "261.2-1", "261.3-1", "repo"),
          P("python", "3.14.0-1", "3.14.1-1", "repo"),
          P("visual-studio-code-bin", "1.140.0-1", "1.141.0-1", "aur"),
          P("Spotify", "", "1.2.97", "flatpak")]
    ws = []
    if os.environ.get("ARCH_UPDATE_GUI_DEMO_WARN") == "1":
        ws.append({"id": "local:kwin-git:kwin:6.7.6-1", "kind": "local", "blocking": False,
                   "title": "kwin-git depodaki kwin sürümünün gerisinde kaldı",
                   "detail": "Kurulu yerel paket kwin 6.7.5 sağlıyor, depoda 6.7.6-1 var. Yeniden derlenmesi gerekebilir; ona bağlı paketler uyumsuz kalabilir."})
    return {"packages": pk, "warnings": ws, "notes": [], "error": ""}


def demo_news_xml():
    time.sleep(0.4)
    now = time.time()
    items = []
    titles = [("Mkinitcpio >=42 requires manual intervention for TPM2-based unlocking of LUKS devices", 12),
              ("Plasma 6.7 drops X11 session support", 30), ("Valkey to replace Redis in [extra]", 60),
              ("glibc 2.42 enforces stricter dlopen checks", 90), ("Arch Linux 2026 leader election results", 120)]
    if os.environ.get("ARCH_UPDATE_GUI_DEMO_WARN") == "1":
        titles.insert(0, ("NVIDIA 590 driver series drops Pascal support", 0.5))
    for t, d in titles:
        items.append(f"<item><title>{html.escape(t)}</title><link>https://archlinux.org/news/x/</link>"
                     f"<description>{html.escape('<p>Starting with package version <code>42-1</code>, the hook now includes a new service. If you unlock LUKS partitions with TPM2 you need to <a href=\"https://wiki.archlinux.org\">re-enroll</a>.</p>')}</description>"
                     f"<pubDate>{email.utils.formatdate(now - d * 86400)}</pubDate><guid>{html.escape(t)}</guid></item>")
    return ("<rss><channel>" + "".join(items) + "</channel></rss>").encode()


def main():
    # Ac/kapa: pencere odak kaybedip kapandiktan hemen sonra tepsiye yeniden tiklandiysa
    # (yani kullanici kapatmak icin tikladiysa) yeniden acma.
    try:
        if time.time() - float(CLOSED_STAMP.read_text()) < 0.45:
            return 0
    except (OSError, ValueError):
        pass

    sock = QLocalSocket()
    sock.connectToServer(SOCKET_NAME)
    if sock.waitForConnected(300):
        sock.write(b"show")
        sock.flush()
        sock.waitForBytesWritten(300)
        return 0

    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "org.kde.desktop")
    QApplication.setDesktopFileName("arch-update")
    app = QApplication(sys.argv)
    app.setApplicationName("arch-update-gui")
    app.setApplicationDisplayName("Arch Güncelleme")
    app.setQuitOnLastWindowClosed(True)

    QLocalServer.removeServer(SOCKET_NAME)
    server = QLocalServer()
    server.listen(SOCKET_NAME)

    backend = Backend()

    def on_conn():
        c = server.nextPendingConnection()
        c.waitForReadyRead(200)
        backend.showRequested.emit()
        c.close()
    server.newConnection.connect(on_conn)

    def on_quit():
        backend.markResultSeen()
        try:
            CLOSED_STAMP.write_text(str(time.time()))
        except OSError:
            pass
    app.aboutToQuit.connect(on_quit)

    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", backend)
    engine.load(QUrl.fromLocalFile(str(HERE / "Popup.qml")))
    if not engine.rootObjects():
        return 1

    # Test: ekran goruntusu (QT_QPA_PLATFORM=offscreen ile) — ARCH_UPDATE_GUI_SHOT=yol
    shot = os.environ.get("ARCH_UPDATE_GUI_SHOT")
    if shot:
        win = engine.rootObjects()[0]
        action = os.environ.get("ARCH_UPDATE_GUI_SHOT_ACTION", "")
        if action == "update":
            QTimer.singleShot(1500, backend.requestUpdate)
        elif action == "confirm":
            QTimer.singleShot(1500, backend.requestUpdate)
        elif action == "news":
            QTimer.singleShot(1500, lambda: win.setProperty("expandedNews", 0))

        def grab():
            win.setProperty("shotPath", shot)
        QTimer.singleShot(int(os.environ.get("ARCH_UPDATE_GUI_SHOT_DELAY", "2500")), grab)
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())

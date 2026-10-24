// arch-update-gui acilir penceresi — sag ust kosede, Plasma
// tepsi acilir pencereleri gibi (layer-shell, panelin altina yaslanir).
// Tek cerceve, bolumler ince sonuk gri cizgilerle ayrilir.

import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.layershell as LayerShell

Window {
    id: win

    readonly property bool busyMode: backend.mode === "updating" || backend.mode === "done"
    property int expandedNews: -1
    property bool armed: false
    // test: arka uc ekran goruntusu yolunu verir, pencere kendini kaydedip kapanir
    property string shotPath: ""
    onShotPathChanged: root.grabToImage(function(r) { console.log("saved", r.saveToFile(shotPath)); Qt.quit() })

    width: Kirigami.Units.gridUnit * 26
    height: Math.min(content.implicitHeight + 2, Screen.height - Kirigami.Units.gridUnit * 4)
    visible: true
    title: "Arch Güncelleme"
    color: "transparent"

    LayerShell.Window.scope: "arch-update-gui"
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorRight
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.exclusionZone: 0
    // Acilista Exclusive: KWin odagi hemen verir (OnDemand'da yalnizca tiklayinca verir).
    // Odak gelince OnDemand'a gecilir — klavye serbest kalir, disari tiklama odagi alip pencereyi kapatir.
    LayerShell.Window.keyboardInteractivity: armed ? LayerShell.Window.KeyboardInteractivityOnDemand
                                                   : LayerShell.Window.KeyboardInteractivityExclusive

    // Tepsi acilir pencereleri gibi: baska yere tiklaninca kapan
    onActiveChanged: {
        if (active) {
            armed = true
        } else if (armed) {
            Qt.quit()
        }
    }

    Component.onCompleted: Qt.callLater(win.requestActivate)

    Connections {
        target: backend
        function onShowRequested() { win.requestActivate() }
    }

    Shortcut {
        sequences: [StandardKey.Cancel]
        onActivated: Qt.quit()
    }

    Rectangle {
    id: root
    anchors.fill: parent
    // Kirigami temasi Window nesnesine degil, bir Item'a baglanmali (yoksa acik/koyu renkler karisiyor)
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false
    color: Kirigami.Theme.backgroundColor

    readonly property int pad: Kirigami.Units.largeSpacing
    readonly property color lineColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.13)
    readonly property color dimText: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.6)

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: root.lineColor
        z: 10
    }

    QQC2.ScrollView {
        id: scroller
        anchors.fill: parent
        anchors.margins: 1
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
        contentWidth: availableWidth

        ColumnLayout {
            id: content
            width: scroller.availableWidth
            spacing: 0

            // ───────────── baslik ─────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: root.pad
                spacing: Kirigami.Units.mediumSpacing

                Kirigami.Icon {
                    source: backend.packages.length > 0 && !win.busyMode ? "cachy-update_updates-available-blue" : "cachy-update-blue"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Kirigami.Heading {
                        level: 4
                        text: "Sistem Güncellemesi"
                        Layout.fillWidth: true
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        color: root.dimText
                        font: Kirigami.Theme.smallFont
                        text: {
                            if (backend.mode === "updating") return "Güncelleme sürüyor"
                            if (backend.mode === "done") return "Güncelleme bitti"
                            if (backend.checking) return "Denetleniyor…"
                            var n = backend.packages.length
                            var s = n > 0 ? n + " güncelleme" : "Sistem güncel"
                            return backend.lastCheck ? s + " · son kontrol " + backend.lastCheck : s
                        }
                    }
                }
                QQC2.ToolButton {
                    icon.name: "view-refresh"
                    enabled: !backend.checking && !win.busyMode
                    onClicked: { backend.refresh(); backend.fetchNews() }
                    QQC2.ToolTip.text: "Yeniden denetle"
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
                QQC2.ToolButton {
                    icon.name: "window-close"
                    onClicked: Qt.quit()
                    QQC2.ToolTip.text: "Kapat (güncelleme arka planda sürer)"
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }

            Line {}

            // ───────────── uyarilar (elle mudahale) ─────────────
            ColumnLayout {
                visible: backend.warnings.length > 0 && !win.busyMode
                Layout.fillWidth: true
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: warnCol.implicitHeight + root.pad * 2
                    color: Qt.rgba(Kirigami.Theme.neutralTextColor.r, Kirigami.Theme.neutralTextColor.g, Kirigami.Theme.neutralTextColor.b, 0.08)

                    Rectangle {
                        width: 3
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        color: backend.blockingCount > 0 ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.neutralTextColor
                    }

                    ColumnLayout {
                        id: warnCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.pad; leftMargin: root.pad + 3 }
                        spacing: Kirigami.Units.smallSpacing

                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon {
                                source: "dialog-warning"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            }
                            QQC2.Label {
                                text: "Elle müdahale gerekebilir"
                                font.bold: true
                            }
                        }
                        Repeater {
                            model: backend.warnings
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 1
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    text: "• " + modelData.title
                                    color: modelData.kind === "news" ? Kirigami.Theme.linkColor : Kirigami.Theme.textColor
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: modelData.kind === "news"
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: win.expandedNews = modelData.newsIndex
                                    }
                                }
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: Kirigami.Units.largeSpacing
                                    visible: text.length > 0 && modelData.kind !== "news"
                                    wrapMode: Text.Wrap
                                    font: modelData.kind === "pacman" ? Kirigami.Theme.fixedWidthFont : Kirigami.Theme.smallFont
                                    color: root.dimText
                                    text: modelData.detail || ""
                                }
                            }
                        }
                    }
                }
                Line {}
            }

            // ───────────── kontrol hatasi ─────────────
            QQC2.Label {
                visible: backend.checkError.length > 0 && !win.busyMode
                Layout.fillWidth: true
                Layout.margins: root.pad
                wrapMode: Text.Wrap
                color: Kirigami.Theme.negativeTextColor
                text: backend.checkError
            }

            // ───────────── paketler ─────────────
            ColumnLayout {
                visible: !win.busyMode
                Layout.fillWidth: true
                spacing: 0

                SectionHeader {
                    text: "Güncellenecek paketler"
                    extra: {
                        var parts = []
                        if (backend.repoCount) parts.push("Depo " + backend.repoCount)
                        if (backend.aurCount) parts.push("AUR " + backend.aurCount)
                        if (backend.flatpakCount) parts.push("Flatpak " + backend.flatpakCount)
                        return parts.join(" · ")
                    }
                }

                RowLayout {
                    visible: backend.packages.length === 0
                    Layout.fillWidth: true
                    Layout.leftMargin: root.pad
                    Layout.rightMargin: root.pad
                    Layout.bottomMargin: root.pad
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.BusyIndicator {
                        visible: backend.checking
                        running: visible
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    }
                    Kirigami.Icon {
                        visible: !backend.checking
                        source: "checkmark"
                        color: Kirigami.Theme.positiveTextColor
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        color: root.dimText
                        text: backend.checking ? "Güncellemeler denetleniyor…" : "Güncellenecek paket yok"
                    }
                }

                ListView {
                    id: pkgList
                    visible: backend.packages.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, Kirigami.Units.gridUnit * 14)
                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                    clip: true
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    model: backend.packages
                    QQC2.ScrollBar.vertical: QQC2.ScrollBar { policy: pkgList.interactive ? QQC2.ScrollBar.AsNeeded : QQC2.ScrollBar.AlwaysOff }

                    delegate: RowLayout {
                        required property var modelData
                        width: ListView.view.width
                        height: Kirigami.Units.gridUnit * 1.25
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            Layout.leftMargin: root.pad
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: modelData.name
                        }
                        QQC2.Label {
                            visible: modelData.source !== "repo"
                            text: modelData.source === "aur" ? "AUR" : "Flatpak"
                            font: Kirigami.Theme.smallFont
                            color: root.dimText
                        }
                        QQC2.Label {
                            Layout.rightMargin: root.pad + (pkgList.interactive ? Kirigami.Units.smallSpacing * 2 : 0)
                            Layout.maximumWidth: pkgList.width * 0.58
                            elide: Text.ElideLeft
                            horizontalAlignment: Text.AlignRight
                            font: Kirigami.Theme.smallFont
                            textFormat: Text.StyledText
                            color: root.dimText
                            function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;") }
                            text: modelData.old
                                  ? esc(modelData.common) + "<font color='" + Kirigami.Theme.negativeTextColor + "'>" + esc(modelData.oldTail) + "</font>"
                                    + " → " + esc(modelData.common) + "<font color='" + Kirigami.Theme.positiveTextColor + "'><b>" + esc(modelData.newTail) + "</b></font>"
                                  : "<font color='" + Kirigami.Theme.positiveTextColor + "'>" + esc(modelData.new) + "</font>"
                        }
                    }
                }
                Line {}
            }

            // ───────────── ilerleme ─────────────
            ColumnLayout {
                visible: backend.mode === "updating"
                Layout.fillWidth: true
                Layout.margins: root.pad
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.BusyIndicator {
                        running: backend.mode === "updating"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: backend.stepLabel
                    }
                    QQC2.Label {
                        visible: backend.progress >= 0
                        color: root.dimText
                        text: Math.round(backend.progress * 100) + "%"
                    }
                }
                QQC2.ProgressBar {
                    Layout.fillWidth: true
                    from: 0; to: 1
                    value: Math.max(backend.progress, 0)
                    indeterminate: backend.progress < 0
                }
                StepStrip { Layout.fillWidth: true }
            }

            // ───────────── sonuc ─────────────
            ColumnLayout {
                id: resultCol
                visible: backend.mode === "done"
                Layout.fillWidth: true
                Layout.margins: root.pad
                spacing: Kirigami.Units.smallSpacing
                readonly property bool ok: backend.result.rc === "0"

                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon {
                        source: resultCol.ok ? "checkmark" : "dialog-error"
                        color: resultCol.ok ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.bold: true
                        text: resultCol.ok ? "Güncelleme tamamlandı" : (backend.result.msg || "Güncelleme başarısız")
                    }
                }
                QQC2.Label {
                    visible: !!backend.result.finished
                    color: root.dimText
                    font: Kirigami.Theme.smallFont
                    text: "Bitiş: " + (backend.result.finished || "")
                }
                ResultRow {
                    visible: !!backend.result.reboot
                    icon: "system-reboot"
                    tone: Kirigami.Theme.neutralTextColor
                    text: "Çekirdek güncellendi — değişikliğin geçmesi için yeniden başlatın."
                    action: "Yeniden başlat…"
                    onTriggered: backend.reboot()
                }
                ResultRow {
                    visible: !!backend.result.pacnew
                    icon: "document-edit"
                    tone: Kirigami.Theme.neutralTextColor
                    text: "Bekleyen yapılandırma dosyaları (.pacnew): " + (backend.result.pacnew || "").split(" ").join(", ")
                }
                ResultRow {
                    visible: !!backend.result.services
                    icon: "system-run"
                    text: "Yeniden başlatılması önerilen servisler: " + (backend.result.services || "").split(" ").join(", ")
                }
                ResultRow {
                    visible: !!backend.result.orphans
                    icon: "edit-delete"
                    text: {
                        var o = (backend.result.orphans || "").split(" ")
                        return "Yetim paketler (" + o.length + ", kaldırılmadı): " + o.slice(0, 8).join(", ") + (o.length > 8 ? " …" : "")
                    }
                }
            }

            // ───────────── gunluk (guncelleme/sonuc) ─────────────
            ColumnLayout {
                visible: win.busyMode
                Layout.fillWidth: true
                spacing: 0
                Line {}
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: root.pad
                    Layout.rightMargin: root.pad / 2
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: "Günlük"
                        font.bold: true
                        color: root.dimText
                    }
                    QQC2.ToolButton {
                        icon.name: logBox.visible ? "arrow-up" : "arrow-down"
                        text: logBox.visible ? "Gizle" : "Göster"
                        display: QQC2.AbstractButton.TextBesideIcon
                        onClicked: logBox.visible = !logBox.visible
                    }
                    QQC2.ToolButton {
                        icon.name: "document-open"
                        onClicked: backend.openLog()
                        QQC2.ToolTip.text: "Günlüğü düzenleyicide aç"
                        QQC2.ToolTip.visible: hovered
                    }
                }
                Rectangle {
                    id: logBox
                    visible: backend.mode === "updating" || backend.result.rc !== "0"
                    Layout.fillWidth: true
                    Layout.leftMargin: root.pad
                    Layout.rightMargin: root.pad
                    Layout.bottomMargin: root.pad
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 10
                    color: Qt.darker(Kirigami.Theme.backgroundColor, 1.25)
                    border.width: 1
                    border.color: root.lineColor

                    QQC2.ScrollView {
                        id: logScroll
                        anchors.fill: parent
                        anchors.margins: 1
                        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
                        property bool follow: true

                        QQC2.TextArea {
                            id: logArea
                            readOnly: true
                            wrapMode: Text.WrapAnywhere
                            font.family: Kirigami.Theme.fixedWidthFont.family
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            text: backend.log
                            background: null
                            onTextChanged: if (logScroll.follow) Qt.callLater(function() { logArea.cursorPosition = logArea.length })
                        }
                    }
                }
                QQC2.Label {
                    visible: backend.mode === "updating"
                    Layout.fillWidth: true
                    Layout.leftMargin: root.pad
                    Layout.rightMargin: root.pad
                    Layout.bottomMargin: root.pad
                    wrapMode: Text.Wrap
                    color: root.dimText
                    font: Kirigami.Theme.smallFont
                    text: "Pencereyi kapatabilirsiniz; güncelleme arka planda sürer ve bitince bildirim gelir."
                }
                Line {}
            }

            // ───────────── Arch haberleri ─────────────
            ColumnLayout {
                visible: backend.mode !== "updating"
                Layout.fillWidth: true
                spacing: 0

                SectionHeader {
                    text: "Arch Haberleri"
                    extra: backend.newsLoading ? "yükleniyor…" : ""
                }
                QQC2.Label {
                    visible: backend.newsError.length > 0
                    Layout.fillWidth: true
                    Layout.leftMargin: root.pad
                    Layout.rightMargin: root.pad
                    Layout.bottomMargin: root.pad
                    wrapMode: Text.Wrap
                    color: Kirigami.Theme.negativeTextColor
                    text: backend.newsError
                }
                Repeater {
                    model: backend.news
                    delegate: ColumnLayout {
                        id: newsItem
                        required property var modelData
                        required property int index
                        readonly property bool expanded: win.expandedNews === index
                        Layout.fillWidth: true
                        spacing: 0

                        QQC2.ItemDelegate {
                            Layout.fillWidth: true
                            leftPadding: root.pad
                            rightPadding: root.pad
                            topPadding: Kirigami.Units.smallSpacing
                            bottomPadding: Kirigami.Units.smallSpacing
                            onClicked: win.expandedNews = newsItem.expanded ? -1 : newsItem.index
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                Kirigami.Icon {
                                    source: newsItem.expanded ? "arrow-down" : "arrow-right"
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                    opacity: 0.6
                                }
                                Rectangle {
                                    visible: newsItem.modelData.isNew
                                    implicitWidth: newTag.implicitWidth + 8
                                    implicitHeight: newTag.implicitHeight + 2
                                    radius: 2
                                    color: Kirigami.Theme.neutralTextColor
                                    QQC2.Label {
                                        id: newTag
                                        anchors.centerIn: parent
                                        text: "YENİ"
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        font.bold: true
                                        color: Kirigami.Theme.backgroundColor
                                    }
                                }
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    elide: newsItem.expanded ? Text.ElideNone : Text.ElideRight
                                    wrapMode: newsItem.expanded ? Text.Wrap : Text.NoWrap
                                    maximumLineCount: newsItem.expanded ? 4 : 1
                                    font.bold: newsItem.modelData.isNew
                                    text: newsItem.modelData.title
                                }
                                QQC2.Label {
                                    color: root.dimText
                                    font: Kirigami.Theme.smallFont
                                    text: newsItem.modelData.date
                                }
                            }
                        }
                        ColumnLayout {
                            visible: newsItem.expanded
                            Layout.fillWidth: true
                            Layout.leftMargin: root.pad + Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing
                            Layout.rightMargin: root.pad
                            Layout.bottomMargin: Kirigami.Units.mediumSpacing
                            spacing: Kirigami.Units.smallSpacing
                            QQC2.Label {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                textFormat: Text.RichText
                                font: Kirigami.Theme.smallFont
                                text: "<style>a{color:" + Kirigami.Theme.linkColor + "} code,pre{font-family:monospace}</style>" + newsItem.modelData.html
                                onLinkActivated: (link) => backend.openUrl(link)
                                HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                            }
                            QQC2.Label {
                                text: "<a href='" + newsItem.modelData.link + "'>Tarayıcıda aç ↗</a>"
                                textFormat: Text.StyledText
                                linkColor: Kirigami.Theme.linkColor
                                font: Kirigami.Theme.smallFont
                                onLinkActivated: (link) => backend.openUrl(link)
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                            }
                        }
                    }
                }
                Item { implicitHeight: Kirigami.Units.smallSpacing }
                Line {}
            }

            // ───────────── onay (yalnizca elle mudahale durumunda) ─────────────
            ColumnLayout {
                visible: backend.mode === "confirm"
                Layout.fillWidth: true
                Layout.margins: root.pad
                spacing: Kirigami.Units.mediumSpacing
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: backend.blockingCount > 0
                          ? "pacman bu güncellemeyi kendiliğinden tamamlayamaz. Soruları yanıtlamak için güncellemeyi terminalde başlatın."
                          : "Yukarıdaki uyarıları okudunuz mu? Güncelleme yine de başlatılsın mı?"
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.Button {
                        text: "Vazgeç"
                        onClicked: backend.cancelConfirm()
                    }
                    Item { Layout.fillWidth: true }
                    QQC2.Button {
                        text: "Terminalde güncelle"
                        icon.name: "utilities-terminal"
                        highlighted: backend.blockingCount > 0
                        onClicked: backend.updateInTerminal()
                    }
                    QQC2.Button {
                        visible: backend.blockingCount === 0
                        text: "Güncelle"
                        icon.name: "update-none"
                        highlighted: true
                        onClicked: backend.startUpdate()
                    }
                }
            }

            // ───────────── alt dugme ─────────────
            QQC2.Button {
                visible: backend.mode === "ready" || backend.mode === "checking" || backend.mode === "done"
                Layout.fillWidth: true
                Layout.margins: root.pad
                highlighted: backend.mode !== "done"
                icon.name: backend.mode === "done" ? "dialog-ok" : "update-none"
                enabled: backend.mode === "done" || (backend.packages.length > 0 && !backend.checking)
                text: {
                    if (backend.mode === "done") return backend.result.rc === "0" ? "Tamam" : "Kapat ve yeniden denetle"
                    if (backend.checking) return "Denetleniyor…"
                    if (backend.packages.length === 0) return "Sistem güncel"
                    return "Güncelle (" + backend.packages.length + " paket)"
                }
                onClicked: backend.mode === "done" ? backend.dismissResult() : backend.requestUpdate()
            }
        }
    }

    }

    component Line: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: root.lineColor
    }

    component SectionHeader: RowLayout {
        property alias text: lbl.text
        property alias extra: ext.text
        Layout.fillWidth: true
        Layout.leftMargin: root.pad
        Layout.rightMargin: root.pad
        Layout.topMargin: Kirigami.Units.mediumSpacing
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        QQC2.Label {
            id: lbl
            Layout.fillWidth: true
            font.bold: true
            color: root.dimText
        }
        QQC2.Label {
            id: ext
            color: root.dimText
            font: Kirigami.Theme.smallFont
        }
    }

    component ResultRow: RowLayout {
        id: rr
        property string icon
        property color tone: Kirigami.Theme.textColor
        property alias text: rl.text
        property string action: ""
        signal triggered()
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        Kirigami.Icon {
            source: rr.icon
            color: rr.tone
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }
        QQC2.Label {
            id: rl
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
        }
        QQC2.Button {
            visible: rr.action.length > 0
            text: rr.action
            onClicked: rr.triggered()
        }
    }

    component StepStrip: RowLayout {
        spacing: Kirigami.Units.smallSpacing
        readonly property var steps: {
            var s = []
            if (backend.repoCount) s.push(["repo", "Depo"])
            if (backend.aurCount) s.push(["aur", "AUR"])
            if (backend.flatpakCount) s.push(["flatpak", "Flatpak"])
            s.push(["post", "Son işlemler"])
            return s
        }
        readonly property int current: {
            for (var i = 0; i < steps.length; i++) if (steps[i][0] === backend.step) return i
            return -1
        }
        Repeater {
            model: parent.steps
            delegate: RowLayout {
                required property var modelData
                required property int index
                spacing: Kirigami.Units.smallSpacing
                QQC2.Label {
                    visible: index > 0
                    text: "›"
                    color: root.dimText
                }
                QQC2.Label {
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: modelData[1]
                    font.bold: index === parent.parent.current
                    color: index === parent.parent.current ? Kirigami.Theme.textColor
                         : index < parent.parent.current ? Kirigami.Theme.positiveTextColor : root.dimText
                }
            }
        }
    }
}

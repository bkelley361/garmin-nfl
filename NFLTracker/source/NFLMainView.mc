import Toybox.Application.Storage;
import Toybox.Attention;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;
using KPayApp.KPay as KPay;

class NFLMainView extends WatchUi.View {

    private var _games as Array<Dictionary> = [];
    private var _index as Number = 0;
    private var _isUpdating as Boolean = false;
    private var _statusMsg as String = "Loading scores...";
    private var _kpay as KPay.Core? = null;

    function initialize() {
        View.initialize();
        if (NFLPayManager.isNFLSeason()) {
            _kpay = new KPay.Core(KPAY_CONFIG);
            if (_kpay != null) {
                _kpay.startPurchase();
            }
        }
        var cached = Storage.getValue("games") as Array<Dictionary>?;
        if (cached != null && cached.size() > 0) {
            _games = cached;
        }
    }

    function onShow() as Void {
        if (NFLPayManager.isUnlocked()) {
            fetchLiveScores();
        }
    }

    function fetchLiveScores() as Void {
        _isUpdating = true;
        _statusMsg = "Updating...";
        WatchUi.requestUpdate();

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(NFLTrackerApp.PROXY_URL, null, options, method(:onReceiveLive));
    }

    function onReceiveLive(responseCode as Number, data as Dictionary or String or Null) as Void {
        _isUpdating = false;
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var fetched = data["games"] as Array<Dictionary>?;
            if (fetched != null && fetched.size() > 0) {
                _games = fetched;
                if (_index >= _games.size()) {
                    _index = 0;
                }
                Storage.setValue("games", _games);
                if (Attention has :vibrate) {
                    Attention.vibrate([new Attention.VibeProfile(50, 100)]);
                }
            } else {
                _statusMsg = "No games scheduled";
            }
        } else {
            _statusMsg = "Sync failed (" + responseCode + ")";
        }
        WatchUi.requestUpdate();
    }

    function nextGame() as Void {
        if (_games.size() > 1) {
            _index = (_index + 1) % _games.size();
            WatchUi.requestUpdate();
        }
    }

    function prevGame() as Void {
        if (_games.size() > 1) {
            _index = (_index - 1 + _games.size()) % _games.size();
            WatchUi.requestUpdate();
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        // OLED True Pitch Black background
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // -------------------------------------------------------------
        // KIEZELPAY SUBSCRIPTION CHECK (Aug - Feb: $4.99)
        // -------------------------------------------------------------
        if (NFLPayManager.isNFLSeason()) {
            if (_kpay != null && _kpay.shouldShowDialog()) {
                _kpay.drawDialog(dc);
                return;
            }
        }

        // -------------------------------------------------------------
        // Empty or Loading State
        // -------------------------------------------------------------
        if (_games.size() == 0) {
            // Center subtle loading card
            dc.setColor(0x131722, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(cx - 120, h / 2 - 50, 240, 100, 16);
            dc.setColor(0x262D3D, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawRoundedRectangle(cx - 120, h / 2 - 50, 240, 100, 16);

            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h / 2 - 15, Graphics.FONT_SMALL, _statusMsg, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            dc.setColor(0x38BDF8, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h / 2 + 20, Graphics.FONT_XTINY, "Tap to refresh", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var g = _games[_index];
        var away = (g["away"] != null) ? (g["away"] as String) : "AWY";
        var home = (g["home"] != null) ? (g["home"] as String) : "HME";
        var awayScore = (g["awayScore"] != null) ? (g["awayScore"] as Number) : 0;
        var homeScore = (g["homeScore"] != null) ? (g["homeScore"] as Number) : 0;
        var status = (g["status"] != null) ? (g["status"] as String) : "";
        var state = (g["state"] != null) ? (g["state"] as String) : "";

        // -------------------------------------------------------------
        // 1. TOP HEADER: Carousel Counter (e.g., "3 of 14")
        // -------------------------------------------------------------
        var counterText = (_index + 1).toString() + " of " + _games.size().toString();
        dc.setColor(0x64748B, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.08, Graphics.FONT_XTINY, counterText, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // -------------------------------------------------------------
        // 2. STATUS PILL BADGE (Live, Final, or Scheduled)
        // -------------------------------------------------------------
        var pillY = h * 0.15;
        var pillH = 24;
        var pillW = dc.getTextWidthInPixels(status, Graphics.FONT_XTINY) + 28;
        if (pillW < 100) { pillW = 100; }
        if (pillW > 220) { pillW = 220; }
        var pillX = cx - (pillW / 2);

        if (state.equals("in")) {
            // Live badge: subtle green glow pill
            dc.setColor(0x1B2E1E, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(pillX, pillY - (pillH / 2), pillW, pillH, 12);
            dc.setColor(0x22C55E, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawRoundedRectangle(pillX, pillY - (pillH / 2), pillW, pillH, 12);

            // Live dot
            dc.setColor(0x22C55E, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(pillX + 13, pillY, 3);

            dc.setColor(0x4ADE80, Graphics.COLOR_TRANSPARENT);
            dc.drawText(pillX + (pillW / 2) + 4, pillY, Graphics.FONT_XTINY, status, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else if (state.equals("post") || status.equals("FINAL")) {
            // Final badge: sleek slate charcoal
            dc.setColor(0x1E222D, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(pillX, pillY - (pillH / 2), pillW, pillH, 12);
            dc.setColor(0x333A48, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawRoundedRectangle(pillX, pillY - (pillH / 2), pillW, pillH, 12);

            dc.setColor(0xCBD5E1, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, pillY, Graphics.FONT_XTINY, "FINAL", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            // Scheduled kickoff badge
            dc.setColor(0x0F1E36, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(pillX, pillY - (pillH / 2), pillW, pillH, 12);
            dc.setColor(0x1E3A8A, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawRoundedRectangle(pillX, pillY - (pillH / 2), pillW, pillH, 12);

            dc.setColor(0x38BDF8, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, pillY, Graphics.FONT_XTINY, status, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // -------------------------------------------------------------
        // 3. MAIN SCOREBOARD CARD (Rounded Glassmorphic Container)
        // -------------------------------------------------------------
        var cardW = (w * 0.84).toNumber();
        var cardH = (h * 0.38).toNumber();
        var cardX = cx - (cardW / 2);
        var cardY = (h * 0.22).toNumber();
        var radius = 16;

        // Card background fill
        dc.setColor(0x131722, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cardX, cardY, cardW, cardH, radius);

        // Card subtle border
        dc.setColor(0x262D3D, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRoundedRectangle(cardX, cardY, cardW, cardH, radius);

        // Center divider line between teams
        var midY = cardY + (cardH / 2);
        dc.setColor(0x1E2433, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(cardX + 12, midY, cardX + cardW - 12, midY);

        // Score colors (leader highlights)
        var awayScoreColor = 0xFFFFFF;
        var homeScoreColor = 0xFFFFFF;
        if (state.equals("in") || state.equals("post")) {
            if (awayScore > homeScore) {
                awayScoreColor = 0xFFFFFF;
                homeScoreColor = 0x64748B;
            } else if (homeScore > awayScore) {
                awayScoreColor = 0x64748B;
                homeScoreColor = 0xFFFFFF;
            }
        }

        // --- ROW A: AWAY TEAM ---
        var rowAY = cardY + (cardH * 0.25);
        // Team color vertical bar
        dc.setColor(NFLTheme.getTeamColor(away), Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cardX + 14, rowAY - 16, 5, 32, 2);

        // Team code
        dc.setColor(NFLTheme.getTeamAccent(away), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cardX + 28, rowAY, Graphics.FONT_LARGE, away, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Score
        var awayScoreStr = (state.equals("pre")) ? "-" : awayScore.toString();
        dc.setColor(awayScoreColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cardX + cardW - 18, rowAY, Graphics.FONT_LARGE, awayScoreStr, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

        // --- ROW B: HOME TEAM ---
        var rowBY = cardY + (cardH * 0.75);
        // Team color vertical bar
        dc.setColor(NFLTheme.getTeamColor(home), Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cardX + 14, rowBY - 16, 5, 32, 2);

        // Team code
        dc.setColor(NFLTheme.getTeamAccent(home), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cardX + 28, rowBY, Graphics.FONT_LARGE, home, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Score
        var homeScoreStr = (state.equals("pre")) ? "-" : homeScore.toString();
        dc.setColor(homeScoreColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cardX + cardW - 18, rowBY, Graphics.FONT_LARGE, homeScoreStr, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

        // -------------------------------------------------------------
        // 4. EVENT DETAILS: WHO SCORED & TURNOVERS
        // -------------------------------------------------------------
        var lastScore = g["lastScore"] as Dictionary?;
        var lastTurnover = g["lastTurnover"] as Dictionary?;

        if (lastScore != null && lastTurnover != null) {
            // BOTH SCORE AND TURNOVER EXIST
            var lsType = (lastScore["type"] != null) ? lastScore["type"].toString() : "TD";
            var lsDesc = (lastScore["desc"] != null) ? lastScore["desc"].toString() : "";
            var toType = (lastTurnover["type"] != null) ? lastTurnover["type"].toString() : "TO";
            var toDesc = (lastTurnover["desc"] != null) ? lastTurnover["desc"].toString() : "";
            var toTag = toType.equals("INTERCEPTION") ? "INT" : "FUM";

            // Row 1: Score play
            var ev1Y = (h * 0.67).toNumber();
            var tag1W = dc.getTextWidthInPixels(lsType, Graphics.FONT_XTINY) + 12;
            var tag1Fill = lsType.equals("TD") ? 0x78350F : 0x075985;
            var tag1Text = lsType.equals("TD") ? 0xFBBF24 : 0x38BDF8;

            dc.setColor(tag1Fill, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(cardX, ev1Y - 9, tag1W, 18, 5);
            dc.setColor(tag1Text, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cardX + (tag1W / 2), ev1Y, Graphics.FONT_XTINY, lsType, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            var fittedScore = fitText(dc, lsDesc, cardW - tag1W - 10);
            dc.drawText(cardX + tag1W + 8, ev1Y, Graphics.FONT_XTINY, fittedScore, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

            // Row 2: Turnover play
            var ev2Y = (h * 0.76).toNumber();
            var tag2W = dc.getTextWidthInPixels(toTag, Graphics.FONT_XTINY) + 12;
            dc.setColor(0x450A0A, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(cardX, ev2Y - 9, tag2W, 18, 5);
            dc.setColor(0xEF4444, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawRoundedRectangle(cardX, ev2Y - 9, tag2W, 18, 5);
            dc.setColor(0xF87171, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cardX + (tag2W / 2), ev2Y, Graphics.FONT_XTINY, toTag, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            dc.setColor(0xFECACA, Graphics.COLOR_TRANSPARENT);
            var fittedTO = fitText(dc, toDesc, cardW - tag2W - 10);
            dc.drawText(cardX + tag2W + 8, ev2Y, Graphics.FONT_XTINY, fittedTO, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        } else if (lastScore != null) {
            // ONLY SCORE EXISTS
            var lsType = (lastScore["type"] != null) ? lastScore["type"].toString() : "TD";
            var lsDesc = (lastScore["desc"] != null) ? lastScore["desc"].toString() : "";
            var lsTeam = (lastScore["team"] != null) ? lastScore["team"].toString() : "";
            var lsClock = (lastScore["clock"] != null) ? lastScore["clock"].toString() : "";

            var ev1Y = (h * 0.67).toNumber();
            var tag1W = dc.getTextWidthInPixels(lsType, Graphics.FONT_XTINY) + 12;
            var tag1Fill = lsType.equals("TD") ? 0x78350F : 0x075985;
            var tag1Text = lsType.equals("TD") ? 0xFBBF24 : 0x38BDF8;

            dc.setColor(tag1Fill, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(cardX, ev1Y - 9, tag1W, 18, 5);
            dc.setColor(tag1Text, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cardX + (tag1W / 2), ev1Y, Graphics.FONT_XTINY, lsType, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            dc.setColor(0x94A3B8, Graphics.COLOR_TRANSPARENT);
            var metaText = lsTeam;
            if (lsClock.length() > 0) {
                metaText += " • " + lsClock;
            }
            dc.drawText(cardX + tag1W + 8, ev1Y, Graphics.FONT_XTINY, metaText, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

            var ev2Y = (h * 0.76).toNumber();
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            var fittedScore = fitText(dc, lsDesc, cardW);
            dc.drawText(cx, ev2Y, Graphics.FONT_XTINY, fittedScore, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        } else if (lastTurnover != null) {
            // ONLY TURNOVER EXISTS
            var toType = (lastTurnover["type"] != null) ? lastTurnover["type"].toString() : "TURNOVER";
            var toDesc = (lastTurnover["desc"] != null) ? lastTurnover["desc"].toString() : "";
            var toClock = (lastTurnover["clock"] != null) ? lastTurnover["clock"].toString() : "";
            var toTag = toType.equals("INTERCEPTION") ? "INT" : "FUM";

            var ev1Y = (h * 0.67).toNumber();
            var tag2W = dc.getTextWidthInPixels(toTag, Graphics.FONT_XTINY) + 12;
            dc.setColor(0x450A0A, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(cardX, ev1Y - 9, tag2W, 18, 5);
            dc.setColor(0xEF4444, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawRoundedRectangle(cardX, ev1Y - 9, tag2W, 18, 5);
            dc.setColor(0xF87171, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cardX + (tag2W / 2), ev1Y, Graphics.FONT_XTINY, toTag, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            dc.setColor(0xEF4444, Graphics.COLOR_TRANSPARENT);
            var toHeader = toType;
            if (toClock.length() > 0) {
                toHeader += " • " + toClock;
            }
            dc.drawText(cardX + tag2W + 8, ev1Y, Graphics.FONT_XTINY, toHeader, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

            var ev2Y = (h * 0.76).toNumber();
            dc.setColor(0xFECACA, Graphics.COLOR_TRANSPARENT);
            var fittedTO = fitText(dc, toDesc, cardW);
            dc.drawText(cx, ev2Y, Graphics.FONT_XTINY, fittedTO, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        } else {
            // PRE-GAME OR SCORELESS LIVE GAME
            var midMsgY = (h * 0.72).toNumber();
            if (state.equals("pre")) {
                dc.setColor(0x38BDF8, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, midMsgY, Graphics.FONT_XTINY, "Kickoff Scheduled", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            } else if (state.equals("in")) {
                dc.setColor(0x64748B, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, midMsgY, Graphics.FONT_XTINY, "Game in progress", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
            // For FINAL / post games: do not show "No scoring plays yet" (keep area clean)
        }

        // -------------------------------------------------------------
        // 5. FOOTER: Carousel Dots & Update Status
        // -------------------------------------------------------------
        var footerY = (h * 0.88).toNumber();
        if (_isUpdating) {
            dc.setColor(0x38BDF8, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, footerY, Graphics.FONT_XTINY, "Syncing scores...", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            var total = _games.size();
            if (total > 1 && total <= 16) {
                var dotSpacing = 10;
                var totalDotsW = (total - 1) * dotSpacing;
                var startX = cx - (totalDotsW / 2);
                for (var d = 0; d < total; d++) {
                    if (d == _index) {
                        dc.setColor(0x38BDF8, Graphics.COLOR_TRANSPARENT);
                        dc.fillCircle(startX + (d * dotSpacing), footerY, 3);
                    } else {
                        dc.setColor(0x334155, Graphics.COLOR_TRANSPARENT);
                        dc.fillCircle(startX + (d * dotSpacing), footerY, 2);
                    }
                }
            } else {
                dc.setColor(0x64748B, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, footerY, Graphics.FONT_XTINY, "Swipe to browse", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
        }
    }

    // Dynamic text trimmer to prevent circular screen clipping
    private function fitText(dc as Graphics.Dc, text as String, maxPx as Number) as String {
        if (dc.getTextWidthInPixels(text, Graphics.FONT_XTINY) <= maxPx) {
            return text;
        }
        var s = text;
        while (s.length() > 4 && dc.getTextWidthInPixels(s + "..", Graphics.FONT_XTINY) > maxPx) {
            s = s.substring(0, s.length() - 1);
        }
        return s + "..";
    }
}

class NFLMainDelegate extends WatchUi.BehaviorDelegate {

    private var _view as NFLMainView?;

    function initialize(view as NFLMainView?) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    private function getView() as NFLMainView? {
        if (_view != null) {
            return _view;
        }
        if (WatchUi has :getCurrentView) {
            var pair = WatchUi.getCurrentView();
            if (pair != null && pair[0] instanceof NFLMainView) {
                return pair[0] as NFLMainView;
            }
        }
        return null;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onNextPage() as Boolean {
        var view = getView();
        if (view != null) {
            view.nextGame();
        }
        return true;
    }

    function onPreviousPage() as Boolean {
        var view = getView();
        if (view != null) {
            view.prevGame();
        }
        return true;
    }

    function onSelect() as Boolean {
        // Pressing Start/Select or tapping screen
        if (!NFLPayManager.isUnlocked()) {
            return true;
        }

        var view = getView();
        if (view != null) {
            view.fetchLiveScores();
        }
        return true;
    }
}

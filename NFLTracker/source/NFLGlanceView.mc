import Toybox.Application.Storage;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

(:glance)
class NFLGlanceView extends WatchUi.GlanceView {

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        try {
            var w = dc.getWidth();
            var h = dc.getHeight();

            // OLED True Black
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.clear();

            // KiezelPay Subscription Check (Aug - Feb: $1/mo)
            if (!NFLPayManager.isUnlocked()) {
                dc.setColor(0xF59E0B, Graphics.COLOR_TRANSPARENT);
                dc.drawText(0, h * 0.30, Graphics.FONT_GLANCE, "NFL Tracker", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
                dc.setColor(0x38BDF8, Graphics.COLOR_TRANSPARENT);
                dc.drawText(0, h * 0.72, Graphics.FONT_XTINY, "Unlock at kzl.io ($4.99)", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
                return;
            }

            var games = Storage.getValue("games") as Array<Dictionary>?;

            // Empty / Syncing State
            if (games == null || games.size() == 0) {
                dc.setColor(0x94A3B8, Graphics.COLOR_TRANSPARENT);
                dc.drawText(0, h * 0.30, Graphics.FONT_GLANCE, "NFL Scores", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
                dc.setColor(0x64748B, Graphics.COLOR_TRANSPARENT);
                dc.drawText(0, h * 0.72, Graphics.FONT_XTINY, "Waiting for sync...", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
                return;
            }

            // Find most relevant game (prioritizes LIVE games, then upcoming games)
            var g = games[0];
            var foundLive = false;
            for (var i = 0; i < games.size(); i++) {
                var item = games[i];
                if (item != null && item instanceof Dictionary) {
                    var st = item["state"];
                    if (st != null && st.equals("in")) {
                        g = item;
                        foundLive = true;
                        break;
                    }
                }
            }
            if (!foundLive) {
                for (var j = 0; j < games.size(); j++) {
                    var itemPre = games[j];
                    if (itemPre != null && itemPre instanceof Dictionary) {
                        var stPre = itemPre["state"];
                        if (stPre != null && stPre.equals("pre")) {
                            g = itemPre;
                            break;
                        }
                    }
                }
            }
            if (!(g instanceof Dictionary)) {
                dc.setColor(0x94A3B8, Graphics.COLOR_TRANSPARENT);
                dc.drawText(0, h * 0.50, Graphics.FONT_GLANCE, "NFL Scores", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
                return;
            }

            var away = (g["away"] != null) ? g["away"].toString() : "AWY";
            var home = (g["home"] != null) ? g["home"].toString() : "HME";
            var status = (g["status"] != null) ? g["status"].toString() : "";
            var state = (g["state"] != null) ? g["state"].toString() : "";

            var awayScoreObj = g["awayScore"];
            var homeScoreObj = g["homeScore"];
            var awayScoreStr = (awayScoreObj != null) ? awayScoreObj.toString() : "0";
            var homeScoreStr = (homeScoreObj != null) ? homeScoreObj.toString() : "0";

            var awayScoreNum = 0;
            var homeScoreNum = 0;
            if (awayScoreObj instanceof Number) {
                awayScoreNum = awayScoreObj;
            } else if (awayScoreObj != null) {
                var parsedAway = awayScoreObj.toString().toNumber();
                if (parsedAway != null) { awayScoreNum = parsedAway; }
            }
            if (homeScoreObj instanceof Number) {
                homeScoreNum = homeScoreObj;
            } else if (homeScoreObj != null) {
                var parsedHome = homeScoreObj.toString().toNumber();
                if (parsedHome != null) { homeScoreNum = parsedHome; }
            }

            var yTop = h * 0.30;
            var curX = 2;

            // --- ROW 1: MATCHUP & SCORES ---
            // Away team color indicator
            var awayColor = NFLTheme.getTeamColor(away);
            dc.setColor(awayColor, Graphics.COLOR_TRANSPARENT);
            if (dc has :fillRoundedRectangle) {
                dc.fillRoundedRectangle(curX, yTop - 7, 4, 15, 2);
            } else {
                dc.fillRectangle(curX, yTop - 7, 4, 15);
            }
            curX += 8;

            // Away team code
            dc.setColor(NFLTheme.getTeamAccent(away), Graphics.COLOR_TRANSPARENT);
            dc.drawText(curX, yTop, Graphics.FONT_GLANCE, away, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            curX += dc.getTextWidthInPixels(away, Graphics.FONT_GLANCE) + 5;

            // Away score (highlight leader)
            var awayScoreColor = 0xFFFFFF;
            var homeScoreColor = 0xFFFFFF;
            if (state.equals("in") || state.equals("post")) {
                if (awayScoreNum > homeScoreNum) {
                    awayScoreColor = 0xFFFFFF; // Leader bright white
                    homeScoreColor = 0x94A3B8; // Trailing muted silver
                } else if (homeScoreNum > awayScoreNum) {
                    awayScoreColor = 0x94A3B8;
                    homeScoreColor = 0xFFFFFF;
                }
            }
            dc.setColor(awayScoreColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(curX, yTop, Graphics.FONT_GLANCE, awayScoreStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            curX += dc.getTextWidthInPixels(awayScoreStr, Graphics.FONT_GLANCE) + 8;

            // Separator '@'
            dc.setColor(0x64748B, Graphics.COLOR_TRANSPARENT);
            dc.drawText(curX, yTop, Graphics.FONT_XTINY, "@", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            curX += dc.getTextWidthInPixels("@", Graphics.FONT_XTINY) + 8;

            // Home team color indicator
            var homeColor = NFLTheme.getTeamColor(home);
            dc.setColor(homeColor, Graphics.COLOR_TRANSPARENT);
            if (dc has :fillRoundedRectangle) {
                dc.fillRoundedRectangle(curX, yTop - 7, 4, 15, 2);
            } else {
                dc.fillRectangle(curX, yTop - 7, 4, 15);
            }
            curX += 8;

            // Home team code
            dc.setColor(NFLTheme.getTeamAccent(home), Graphics.COLOR_TRANSPARENT);
            dc.drawText(curX, yTop, Graphics.FONT_GLANCE, home, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            curX += dc.getTextWidthInPixels(home, Graphics.FONT_GLANCE) + 5;

            // Home score
            dc.setColor(homeScoreColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(curX, yTop, Graphics.FONT_GLANCE, homeScoreStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

            // --- ROW 2: STATUS BADGE ---
            var yBottom = h * 0.74;
            if (state.equals("in")) {
                // Live pulsing green dot
                dc.setColor(0x22C55E, Graphics.COLOR_TRANSPARENT);
                if (dc has :fillCircle) {
                    dc.fillCircle(5, yBottom, 3);
                } else {
                    dc.fillRectangle(2, yBottom - 3, 6, 6);
                }
                dc.setColor(0x4ADE80, Graphics.COLOR_TRANSPARENT);
                dc.drawText(14, yBottom, Graphics.FONT_XTINY, status, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            } else if (state.equals("post") || status.equals("FINAL")) {
                // Sleek Final status
                dc.setColor(0x94A3B8, Graphics.COLOR_TRANSPARENT);
                dc.drawText(2, yBottom, Graphics.FONT_XTINY, "FINAL", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            } else {
                // Upcoming game kickoff
                dc.setColor(0x38BDF8, Graphics.COLOR_TRANSPARENT);
                dc.drawText(2, yBottom, Graphics.FONT_XTINY, status, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            }
        } catch (ex) {
            // Failsafe error recovery: never display IQ! icon
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.clear();
            dc.setColor(0x94A3B8, Graphics.COLOR_TRANSPARENT);
            dc.drawText(0, dc.getHeight() / 2, Graphics.FONT_GLANCE, "NFL Scores", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}

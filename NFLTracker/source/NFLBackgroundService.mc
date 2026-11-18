import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

(:background)
class NFLBackgroundService extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        // If unpaid during the NFL season, do not poll scores; check back in an hour
        if (!NFLPayManager.isUnlocked()) {
            scheduleNextWake(60 * 60);
            Background.exit(null);
            return;
        }

        // Fetch all NFL games
        var url = NFLTrackerApp.PROXY_URL;

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        Communications.makeWebRequest(url, null, options, method(:onReceive));
    }

    function onReceive(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var newGames = data["games"] as Array<Dictionary>?;
            if (newGames != null && newGames.size() > 0) {
                // Check all games for score changes and turnovers to trigger watch notifications
                checkAllScoreChanges(newGames);

                // Commit updated games directly to storage so subsequent background runs
                // have the latest baseline to detect subsequent scores/turnovers
                Storage.setValue("games", newGames);

                // Read server-calculated smart battery polling directive
                var nextSec = 300;
                var pollInfo = data["poll"] as Dictionary?;
                if (pollInfo != null && pollInfo["nextPollSeconds"] != null) {
                    var n = pollInfo["nextPollSeconds"];
                    if (n instanceof Number) {
                        nextSec = n as Number;
                    }
                } else {
                    // Fallback: check if ANY game is currently live
                    var anyLive = false;
                    for (var i = 0; i < newGames.size(); i++) {
                        var st = newGames[i]["state"];
                        if (st != null && st.equals("in")) {
                            anyLive = true;
                            break;
                        }
                    }
                    nextSec = anyLive ? (5 * 60) : (60 * 60);
                }

                // Schedule next wake-up
                scheduleNextWake(nextSec);

                Background.exit(newGames);
                return;
            }
        }

        // On error or no games returned, back off to 60 minutes
        scheduleNextWake(60 * 60);
        Background.exit(null);
    }

    // Garmin minimum temporal event interval is 5 minutes (300 sec)
    private function scheduleNextWake(seconds as Number) as Void {
        if (Toybox.System has :ServiceDelegate) {
            if (seconds < 300) {
                seconds = 300;
            }
            Background.registerForTemporalEvent(new Time.Duration(seconds));
        }
    }

    private function getScore(scoreVal as Object?) as Number {
        if (scoreVal instanceof Number) {
            return scoreVal as Number;
        } else if (scoreVal != null) {
            var n = scoreVal.toString().toNumber();
            if (n != null) { return n; }
        }
        return 0;
    }

    // Inspects EVERY game in the NFL slate to detect score changes (with scorer) and turnovers
    private function checkAllScoreChanges(newGames as Array<Dictionary>) as Void {
        var oldGames = Storage.getValue("games") as Array<Dictionary>?;
        if (oldGames == null || oldGames.size() == 0) {
            return;
        }

        // Build a lookup map of previous game states by game ID
        var oldMap = {} as Dictionary;
        for (var i = 0; i < oldGames.size(); i++) {
            var og = oldGames[i];
            if (og != null && og["id"] != null) {
                oldMap.put(og["id"].toString(), og);
            }
        }

        var alerts = [] as Array<String>;

        // Compare each game against previous state
        for (var j = 0; j < newGames.size(); j++) {
            var cur = newGames[j];
            if (cur == null || cur["id"] == null) {
                continue;
            }

            var curId = cur["id"].toString();
            if (!oldMap.hasKey(curId)) {
                continue;
            }

            var prev = oldMap.get(curId) as Dictionary;
            var awayScoreCur = getScore(cur["awayScore"]);
            var awayScorePrev = getScore(prev["awayScore"]);
            var homeScoreCur = getScore(cur["homeScore"]);
            var homeScorePrev = getScore(prev["homeScore"]);

            var awayDiff = awayScoreCur - awayScorePrev;
            var homeDiff = homeScoreCur - homeScorePrev;

            // 1. SCORE CHANGE DETECTED
            if (awayDiff > 0 || homeDiff > 0) {
                var scoringTeam = (awayDiff > 0) ? cur["away"] : cur["home"];
                var diff = (awayDiff > 0) ? awayDiff : homeDiff;
                var eventType = "SCORE";
                if (diff == 6 || diff == 7 || diff == 8) {
                    eventType = "TOUCHDOWN";
                } else if (diff == 3) {
                    eventType = "FIELD GOAL";
                } else if (diff == 2) {
                    eventType = "SAFETY";
                }

                var scoreLine = eventType + " " + scoringTeam + "!\n";

                // Include who scored (player details) if provided by proxy
                var ls = cur["lastScore"] as Dictionary?;
                if (ls != null && ls["desc"] != null) {
                    var desc = ls["desc"].toString();
                    if (desc.length() > 0) {
                        scoreLine += desc + "\n";
                    }
                }

                scoreLine += cur["away"] + " " + awayScoreCur + " - " + cur["home"] + " " + homeScoreCur;
                alerts.add(scoreLine);
            }

            // 2. NEW TURNOVER DETECTED
            var curTo = cur["lastTurnover"] as Dictionary?;
            if (curTo != null && curTo["id"] != null) {
                var curToId = curTo["id"].toString();
                var prevTo = prev["lastTurnover"] as Dictionary?;
                var prevToId = (prevTo != null && prevTo["id"] != null) ? prevTo["id"].toString() : "";

                if (!curToId.equals(prevToId) && curToId.length() > 0) {
                    var toType = (curTo["type"] != null) ? curTo["type"].toString() : "TURNOVER";
                    var toDesc = (curTo["desc"] != null) ? curTo["desc"].toString() : "";
                    var toTeam = (curTo["team"] != null) ? curTo["team"].toString() : "";

                    var toLine = toType + "!\n";
                    if (toDesc.length() > 0) {
                        toLine += toDesc + "\n";
                    } else if (toTeam.length() > 0) {
                        toLine += toTeam + " " + toType + "\n";
                    }
                    toLine += cur["away"] + " vs " + cur["home"];
                    alerts.add(toLine);
                }
            }
        }

        // If any score or turnover occurred, alert user via watch pop-up & vibration
        if (alerts.size() > 0) {
            var fullAlert = "";
            if (alerts.size() == 1) {
                fullAlert = alerts[0];
            } else {
                for (var k = 0; k < alerts.size() && k < 2; k++) {
                    if (k > 0) {
                        fullAlert += "\n---\n";
                    }
                    fullAlert += alerts[k];
                }
                if (alerts.size() > 2) {
                    fullAlert += "\n+" + (alerts.size() - 2) + " more";
                }
            }

            // Safety limit: Garmin wake dialog character limit
            if (fullAlert.length() > 240) {
                fullAlert = fullAlert.substring(0, 237) + "...";
            }

            // requestApplicationWake vibrates the watch and shows the pop-up on the watch face
            if (Background has :requestApplicationWake) {
                Background.requestApplicationWake(fullAlert);
            }
        }
    }
}

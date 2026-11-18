Building a Live NFL Scoreboard & Alert App for Garmin Watches

Garmin watches run apps built with Garmin Connect IQ and programmed in Monkey C. Because watches have tight memory limits (often 32 KB to 128 KB for widgets and background services) and rely on your phone's Bluetooth connection for internet access, building a reliable NFL tracker requires a two-part architecture:

A Lightweight Serverless Proxy: Fetches ESPN's free NFL scoreboard JSON and trims it from ~150 KB down to ~1 KB so your watch never runs out of memory.

A Connect IQ Widget with a Glance & Background Service: Displays live scores directly in your watch's Glance loop, lets you scroll through games, and vibrates/wakes your watch when scores change.

Step 1: Development Environment Setup

Install Java Runtime Environment (JRE 8+): Required by the Monkey C compiler.

Download the Connect IQ SDK Manager:

Go to developer.garmin.com/connect-iq and download the SDK Manager.

Sign in with your Garmin account, download the latest Connect IQ SDK, and download the Device Profile for your specific watch model (e.g., Forerunner 965, Fenix 7/8, Venu 3).

Configure Visual Studio Code:

Install the official Monkey C extension by Garmin.

Open the Command Palette (Cmd+Shift+P on macOS or Ctrl+Shift+P on Windows) and run Monkey C: Verify Installation.

Run Monkey C: Generate a Developer Key and save the .der file in a safe directory (you will need this key to sign builds).

Step 2: Deploy the Lightweight Serverless Proxy

ESPN's public scoreboard API (https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard) requires no API key, but its raw JSON is far too large for a watch's JSON parser.

Deploy the following Cloudflare Worker (free tier handles 100,000 requests/day and provides valid HTTPS out of the box, which Garmin requires):

Cloudflare Worker (worker.js)

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const favTeam = url.searchParams.get("team")?.toUpperCase() || null;

    const espnUrl = "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard";

    try {
      const response = await fetch(espnUrl, {
        cf: { cacheTtl: 30, cacheEverything: true } // Cache for 30s at the edge
      });

      if (!response.ok) {
        return new Response(JSON.stringify({ error: "Upstream error" }), {
          status: 502,
          headers: { "Content-Type": "application/json" }
        });
      }

      const raw = await response.json();
      const events = raw.events || [];

      const games = events.map((event) => {
        const comp = event.competitions?.[0];
        const competitors = comp?.competitors || [];

        const home = competitors.find((c) => c.homeAway === "home") || {};
        const away = competitors.find((c) => c.homeAway === "away") || {};

        const statusType = comp?.status?.type || {};
        const state = statusType.state; // "pre", "in", or "post"

        let shortStatus = statusType.shortDetail || "";
        // Compact status strings for small watch screens
        if (state === "post") {
          shortStatus = "FINAL";
        } else if (state === "in") {
          shortStatus = `Q${comp.status.period} ${comp.status.displayClock}`;
        }

        return {
          id: event.id,
          away: away.team?.abbreviation || "AWY",
          awayScore: parseInt(away.score || "0", 10),
          home: home.team?.abbreviation || "HME",
          homeScore: parseInt(home.score || "0", 10),
          status: shortStatus,
          state: state
        };
      });

      // Optionally filter to a single favorite team if ?team=DET is passed
      const filteredGames = favTeam
        ? games.filter((g) => g.away === favTeam || g.home === favTeam)
        : games;

      return new Response(JSON.stringify({ games: filteredGames }), {
        status: 200,
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": "public, max-age=30"
        }
      });
    } catch (err) {
      return new Response(JSON.stringify({ error: "Proxy failure" }), {
        status: 500,
        headers: { "Content-Type": "application/json" }
      });
    }
  }
};


Example Proxy Output (~350 bytes)

{
  "games": [
    {
      "id": "401671789",
      "away": "DET",
      "awayScore": 24,
      "home": "GB",
      "homeScore": 17,
      "status": "Q4 02:14",
      "state": "in"
    }
  ]
}


Deployment Tip: Create a Worker in the Cloudflare Dashboard, paste this code, click Deploy, and note your *.workers.dev HTTPS URL.

Step 3: Create the Garmin Connect IQ Project

In VS Code, open the Command Palette and run Monkey C: Create New Project.

Name it NFLTracker, choose Widget as the project type, and select your target watch device(s).

Replace the generated files with the structure below.

Project Structure

NFLTracker/
├── manifest.xml
├── monkey.jungle
└── source/
    ├── NFLTrackerApp.mc
    ├── NFLGlanceView.mc
    ├── NFLMainView.mc
    └── NFLBackgroundService.mc


Step 4: Configure manifest.xml

Ensure Communications and Background permissions are enabled so your watch can fetch data over Bluetooth and run periodic background checks.

<?xml version="1.0"?>
<iq:manifest xmlns:iq="http://www.garmin.com/xml/connectiq" version="3">
    <iq:application entry="NFLTrackerApp" id="a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d" launcherIcon="@Drawables.LauncherIcon" minApiLevel="3.2.0" name="@Strings.AppName" type="widget" version="1.0.0">
        <iq:products>
            <!-- Add your watch product IDs here via VS Code: "Monkey C: Edit Products" -->
            <iq:product id="forerunner965"/>
            <iq:product id="fenix7"/>
        </iq:products>
        <iq:permissions>
            <iq:uses-permission id="Communications"/>
            <iq:uses-permission id="Background"/>
        </iq:permissions>
        <iq:languages>
            <iq:language>eng</iq:language>
        </iq:languages>
    </iq:application>
</iq:manifest>


Step 5: Monkey C Source Code

1. source/NFLTrackerApp.mc

Manages the app lifecycle, registers the 5-minute background polling timer, and connects the Glance view, Main view, and Background service.

import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

(:background)
class NFLTrackerApp extends Application.AppBase {

    // Replace with your deployed Cloudflare Worker URL
    public static const PROXY_URL = "https://nfl-proxy.your-subdomain.workers.dev";
    // Set your favorite team abbreviation for glance priority & alerts (or "" for all)
    public static const FAV_TEAM = "DET";

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        // Register background temporal event every 5 minutes (Garmin's minimum interval)
        if (Toybox.System has :ServiceDelegate) {
            Background.registerForTemporalEvent(new Time.Duration(5 * 60));
        }
    }

    function onStop(state as Dictionary?) as Void {
    }

    // Main full-screen widget view
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new NFLMainView(), new NFLMainDelegate()];
    }

    // Small preview card in the watch's widget/glance carousel
    (:glance)
    function getGlanceView() as [GlanceView] or [GlanceView, GlanceViewDelegate] or Null {
        return [new NFLGlanceView()];
    }

    // Background service entry point
    function getServiceDelegate() as [ServiceDelegate] {
        return [new NFLBackgroundService()];
    }

    // Triggered when background service calls Background.exit(data)
    function onBackgroundData(data as Application.PersistableType) as Void {
        if (data != null) {
            Storage.setValue("games", data);
            WatchUi.requestUpdate();
        }
    }
}


2. source/NFLBackgroundService.mc

Runs silently every 5 minutes in the background, fetches the latest JSON from your proxy, compares scores against Application.Storage, and wakes the watch with an alert if your team's score changes.

import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;

(:background)
class NFLBackgroundService extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var url = NFLTrackerApp.PROXY_URL;
        if (!NFLTrackerApp.FAV_TEAM.equals("")) {
            url = url + "?team=" + NFLTrackerApp.FAV_TEAM;
        }

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
                checkScoreChange(newGames);
                Background.exit(newGames);
                return;
            }
        }
        Background.exit(null);
    }

    private function checkScoreChange(newGames as Array<Dictionary>) as Void {
        var oldGames = Storage.getValue("games") as Array<Dictionary>?;
        if (oldGames == null || oldGames.size() == 0) {
            return;
        }

        var current = newGames[0];
        var previous = oldGames[0];

        if (current["id"].equals(previous["id"])) {
            var awayChanged = current["awayScore"] != previous["awayScore"];
            var homeChanged = current["homeScore"] != previous["homeScore"];

            if (awayChanged || homeChanged) {
                var alertMsg = current["away"] + " " + current["awayScore"] +
                               " - " + current["home"] + " " + current["homeScore"] +
                               " (" + current["status"] + ")";
                // Prompts user on watch face to open widget with score update
                Background.requestApplicationWake(alertMsg);
            }
        }
    }
}


3. source/NFLGlanceView.mc

Renders the compact score summary right on your watch's Glance list without needing to open the app.

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
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var games = Storage.getValue("games") as Array<Dictionary>?;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        if (games == null || games.size() == 0) {
            dc.drawText(0, height / 2, Graphics.FONT_GLANCE, "NFL: Waiting for sync...", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var g = games[0];
        var scoreLine = g["away"] + " " + g["awayScore"] + "  @  " + g["home"] + " " + g["homeScore"];
        var statusLine = g["status"];

        dc.drawText(0, height * 0.32, Graphics.FONT_GLANCE, scoreLine, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, height * 0.72, Graphics.FONT_GLANCE_NUMBER, statusLine, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}


4. source/NFLMainView.mc

Displays the full-screen scoreboard when you tap into the Glance, fetches live updates immediately on open, and lets you press Up / Down (or swipe) to cycle through all active NFL games.

import Toybox.Application.Storage;
import Toybox.Attention;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class NFLMainView extends WatchUi.View {

    private var _games as Array<Dictionary> = [];
    private var _index as Number = 0;
    private var _statusMsg as String = "Loading scores...";

    function initialize() {
        View.initialize();
        var cached = Storage.getValue("games") as Array<Dictionary>?;
        if (cached != null && cached.size() > 0) {
            _games = cached;
        }
    }

    function onShow() as Void {
        fetchLiveScores();
    }

    function fetchLiveScores() as Void {
        _statusMsg = "Updating...";
        WatchUi.requestUpdate();

        // Fetch all games for the full-screen view
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(NFLTrackerApp.PROXY_URL, null, options, method(:onReceiveLive));
    }

    function onReceiveLive(responseCode as Number, data as Dictionary or String or Null) as Void {
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

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        if (_games.size() == 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2, Graphics.FONT_SMALL, _statusMsg, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var g = _games[_index];

        // Header: Game index (e.g., "1 / 14")
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.16, Graphics.FONT_XTINY, (_index + 1) + " / " + _games.size(), Graphics.TEXT_JUSTIFY_CENTER);

        // Away Team & Score
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * 0.25, h * 0.35, Graphics.FONT_MEDIUM, g["away"], Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(w * 0.75, h * 0.35, Graphics.FONT_MEDIUM, g["awayScore"].toString(), Graphics.TEXT_JUSTIFY_RIGHT);

        // Home Team & Score
        dc.drawText(w * 0.25, h * 0.52, Graphics.FONT_MEDIUM, g["home"], Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(w * 0.75, h * 0.52, Graphics.FONT_MEDIUM, g["homeScore"].toString(), Graphics.TEXT_JUSTIFY_RIGHT);

        // Game Status / Clock
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.74, Graphics.FONT_SMALL, g["status"], Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class NFLMainDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onNextPage() as Boolean {
        var view = WatchUi.getCurrentView()[0] as NFLMainView;
        view.nextGame();
        return true;
    }

    function onPreviousPage() as Boolean {
        var view = WatchUi.getCurrentView()[0] as NFLMainView;
        view.prevGame();
        return true;
    }

    function onSelect() as Boolean {
        // Pressing Start/Select manually refreshes scores
        var view = WatchUi.getCurrentView()[0] as NFLMainView;
        view.fetchLiveScores();
        return true;
    }
}


Step 6: Test & Sideload onto Your Watch

Test in the Simulator:

Press F5 in VS Code to launch your watch in the Connect IQ Simulator.

In the Simulator menu, go to Simulation > Background Events to manually trigger onTemporalEvent() without waiting 5 minutes.

Sideload to Your Physical Watch:

In VS Code, run Monkey C: Build for Device, select your watch model, and choose an output folder. This generates a .prg binary file.

Connect your Garmin watch to your computer via USB (on macOS, use OpenMTP if your watch uses Media Transfer Protocol).

Copy the .prg file into the watch's GARMIN/APPS/ folder.

Unplug the watch—your NFL widget will appear in your Glance carousel!

import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

(:background)
class NFLTrackerApp extends Application.AppBase {

    // Deployed Cloudflare Worker URL (replace with your worker URL from .env)
    public static const PROXY_URL = "https://nfl-proxy.<your-subdomain>.workers.dev";

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        // Register background temporal event (Garmin's minimum interval)
        if (Toybox.System has :ServiceDelegate) {
            Background.registerForTemporalEvent(new Time.Duration(5 * 60));
        }
    }

    function onStop(state as Dictionary?) as Void {
    }

    // Main full-screen widget view
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new NFLMainView();
        return [view, new NFLMainDelegate(view)];
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

function getApp() as NFLTrackerApp {
    return Application.getApp() as NFLTrackerApp;
}

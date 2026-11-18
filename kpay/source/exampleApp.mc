using Toybox.Application;
import Toybox.WatchUi;
import Toybox.Lang;

// import the KiezelPay functionality from the barrel
using KPayApp.KPay as KPay;

// make sure this variable is also accessible from your View
var kpay as KPay.Core?;

class exampleApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state) {
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
    }

    // Return the initial view of your application here
    function getInitialView() {
        // make sure to always initialize KiezelPay at startup. Supply the KPAY_CONFIG you have defined in kpay_config.mc as parameter
        kpay = new KPay.Core(KPAY_CONFIG);

        // In case you have set TRIAL_ENABLED to false in your config, make sure to call "kpay.startPurchase()" 
        // when you want to start the purchase process
        //
        // In case you have set TRIAL_ENABLED to true in your config, there is no need to call this function,
        // the purchase process will start automatically.
        kpay.startPurchase();
        
        return [ new exampleView() ] as Array<Views or InputDelegates>;
    }
}

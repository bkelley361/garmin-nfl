using Toybox.WatchUi;

class exampleView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    // Load your resources here
    function onLayout(dc) {
        setLayout(Rez.Layouts.MainLayout(dc));
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() {
    }

    // Update the view
    function onUpdate(dc) {
        // in your view, always check if KiezelPay wants to display something
        if ((kpay as KPayApp.KPay.Core).shouldShowDialog()) {
          // in case KiezelPay wants to display something, allow it to draw it's dialog
          (kpay as KPayApp.KPay.Core).drawDialog(dc);
        } else {
          // Call the parent onUpdate function to redraw the layout
          View.onUpdate(dc);
        }
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() {
    }

}

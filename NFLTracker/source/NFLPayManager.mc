import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:glance, :background)
class NFLPayManager {

    // Checks if current date is within the NFL Season (August to February)
    // March 1st through July 31st is the offseason and runs 100% free!
    public static function isNFLSeason() as Boolean {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        // Months in Monkey C are 1 (Jan) through 12 (Dec)
        // Active NFL season: Aug (8), Sep (9), Oct (10), Nov (11), Dec (12), Jan (1), Feb (2)
        return (info.month >= 8 || info.month <= 2);
    }

    // Checks whether the user is authorized to use the app
    public static function isUnlocked() as Boolean {
        // 1. Offseason is completely free!
        if (!isNFLSeason()) {
            return true;
        }

        // 2. Persistent KiezelPay license check (set by official KPay library)
        var licensed = Storage.getValue("kpay_islicensed") as Boolean?;
        return (licensed != null && licensed == true);
    }
}

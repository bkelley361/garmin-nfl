import Toybox.Graphics;
import Toybox.Lang;

(:glance)
class NFLTheme {

    // Primary team brand color
    public static function getTeamColor(team as String?) as Number {
        if (team == null) { return 0x334155; }
        if (team.equals("ARI")) { return 0x97233F; } // Cardinals Cardinal Red
        if (team.equals("ATL")) { return 0xA71930; } // Falcons Red
        if (team.equals("BAL")) { return 0x241773; } // Ravens Purple
        if (team.equals("BUF")) { return 0x00338D; } // Bills Royal Blue
        if (team.equals("CAR")) { return 0x0085CA; } // Panthers Blue
        if (team.equals("CHI")) { return 0xC83803; } // Bears Orange
        if (team.equals("CIN")) { return 0xFB4F14; } // Bengals Orange
        if (team.equals("CLE")) { return 0x311D00; } // Browns Brown
        if (team.equals("DAL")) { return 0x003594; } // Cowboys Blue
        if (team.equals("DEN")) { return 0xFB4F14; } // Broncos Orange
        if (team.equals("DET")) { return 0x0076B6; } // Lions Honolulu Blue
        if (team.equals("GB"))  { return 0x203731; } // Packers Green
        if (team.equals("HOU")) { return 0x03202F; } // Texans Deep Steel Blue
        if (team.equals("IND")) { return 0x002C5F; } // Colts Blue
        if (team.equals("JAX")) { return 0x006778; } // Jaguars Teal
        if (team.equals("KC"))  { return 0xE31837; } // Chiefs Red
        if (team.equals("LV"))  { return 0x708090; } // Raiders Slate/Silver
        if (team.equals("LAC")) { return 0x0080C6; } // Chargers Powder Blue
        if (team.equals("LAR")) { return 0x003594; } // Rams Royal Blue
        if (team.equals("MIA")) { return 0x008E97; } // Dolphins Aqua
        if (team.equals("MIN")) { return 0x4F2683; } // Vikings Purple
        if (team.equals("NE"))  { return 0x002244; } // Patriots Navy
        if (team.equals("NO"))  { return 0xD3BC8D; } // Saints Gold
        if (team.equals("NYG")) { return 0x0B2265; } // Giants Blue
        if (team.equals("NYJ")) { return 0x125740; } // Jets Green
        if (team.equals("PHI")) { return 0x004C54; } // Eagles Midnight Green
        if (team.equals("PIT")) { return 0xFFB612; } // Steelers Gold
        if (team.equals("SF"))  { return 0xAA0000; } // 49ers Red
        if (team.equals("SEA")) { return 0x002244; } // Seahawks Navy
        if (team.equals("TB"))  { return 0xD50A0A; } // Buccaneers Red
        if (team.equals("TEN")) { return 0x0C2340; } // Titans Navy
        if (team.equals("WAS")) { return 0x5A1414; } // Commanders Burgundy
        return 0x334155; // Default Slate
    }

    // High-visibility accent color for dark OLED screens
    public static function getTeamAccent(team as String?) as Number {
        if (team == null) { return 0x94A3B8; }
        if (team.equals("BAL") || team.equals("MIN")) { return 0xC084FC; } // Bright Purple
        if (team.equals("GB") || team.equals("NYJ") || team.equals("PHI")) { return 0x4ADE80; } // Bright Neon Green
        if (team.equals("DET") || team.equals("CAR") || team.equals("LAC")) { return 0x38BDF8; } // Bright Cyan/Sky
        if (team.equals("KC") || team.equals("TB") || team.equals("ATL") || team.equals("SF") || team.equals("ARI")) { return 0xF87171; } // Bright Coral
        if (team.equals("CIN") || team.equals("CHI") || team.equals("DEN")) { return 0xFB923C; } // Bright Orange
        if (team.equals("MIA") || team.equals("JAX")) { return 0x2DD4BF; } // Bright Teal
        if (team.equals("PIT") || team.equals("NO")) { return 0xFACC15; } // Bright Yellow/Gold
        if (team.equals("LV")) { return 0xE2E8F0; } // Silver
        if (team.equals("DAL") || team.equals("BUF") || team.equals("NE") || team.equals("NYG") || team.equals("IND") || team.equals("TEN") || team.equals("SEA")) { return 0x60A5FA; } // Vibrant Blue
        return 0xE2E8F0;
    }
}

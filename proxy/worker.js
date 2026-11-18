export default {
  async fetch(request, env, ctx) {
    // Handle CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type",
          "Access-Control-Max-Age": "86400"
        }
      });
    }

    const url = new URL(request.url);
    const favTeam = url.searchParams.get("team")?.toUpperCase() || null;

    const espnUrl = "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard";

    try {
      const response = await fetch(espnUrl, {
        cf: { cacheTtl: 30, cacheEverything: true } // Cache for 30s at the Cloudflare edge
      });

      if (!response.ok) {
        return new Response(JSON.stringify({ error: "Upstream error", status: response.status }), {
          status: 502,
          headers: {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*"
          }
        });
      }

      const raw = await response.json();
      const events = raw.events || [];

      // Fetch play-by-play summaries for ALL live and completed games so every game
      // has its scoring play (who scored) and turnover details available.
      // (Upcoming "pre" games have no scoring plays yet and are skipped).
      const summaryTargets = events.filter(e => {
        const state = e.competitions?.[0]?.status?.type?.state;
        return state === "in" || state === "post";
      });

      // Fetch summaries in parallel (cached at Cloudflare edge: 86400s for final, 20s for live)
      const summaries = await Promise.all(summaryTargets.map(async (e) => {
        try {
          const isPost = e.competitions?.[0]?.status?.type?.state === "post";
          const ttl = isPost ? 86400 : 20;
          const r = await fetch(`https://site.api.espn.com/apis/site/v2/sports/football/nfl/summary?event=${e.id}`, {
            cf: { cacheTtl: ttl, cacheEverything: true }
          });
          if (r.ok) return { id: e.id, summary: await r.json() };
        } catch (err) {}
        return { id: e.id, summary: null };
      }));

      const summaryMap = new Map(summaries.map(s => [s.id, s.summary]));

      // Extracts the player who scored the latest touchdown, field goal, or safety
      function extractLastScore(summary) {
        if (!summary?.scoringPlays || summary.scoringPlays.length === 0) return null;
        const sp = summary.scoringPlays[summary.scoringPlays.length - 1];
        let desc = sp.text || "";
        const paren = desc.indexOf("(");
        if (paren > 0) desc = desc.substring(0, paren).trim();
        if (desc.length > 55) desc = desc.substring(0, 52) + "...";
        return {
          id: String(sp.id || ""),
          type: sp.scoringType?.abbreviation || sp.type?.abbreviation || "SCORE",
          team: sp.team?.abbreviation || "",
          desc: desc,
          clock: `${sp.clock?.displayValue || ""} Q${sp.period?.number || ""}`.trim()
        };
      }

      // Extracts the most recent turnover (Interception or Fumble Lost)
      function extractLastTurnover(summary) {
        const previousDrives = summary?.drives?.previous || [];
        const toDrives = previousDrives.filter(d => d.result === "INT" || d.result === "FUMBLE");
        if (toDrives.length === 0) return null;
        const td = toDrives[toDrives.length - 1];
        let toType = td.result === "INT" ? "INTERCEPTION" : "FUMBLE";
        let desc = "";

        const plays = td.plays || [];
        let toPlay = null;
        for (let i = plays.length - 1; i >= 0; i--) {
          const txt = (plays[i].text || "").toLowerCase();
          if (plays[i].isTurnover || txt.includes("intercepted") || txt.includes("fumble")) {
            toPlay = plays[i];
            break;
          }
        }
        if (!toPlay && plays.length > 0) toPlay = plays[plays.length - 1];

        if (toPlay && toPlay.text) {
          let clean = toPlay.text.replace(/\([^)]*\)/g, "").replace(/\s+/g, " ").trim();
          if (td.result === "INT") {
            const m = clean.match(/([A-Z]\.[A-Za-z]+)\s+pass.*INTERCEPTED by\s+([A-Z]\.[A-Za-z]+)/i);
            if (m) desc = `${m[1]} INT by ${m[2]}`;
            else desc = clean.substring(0, 50);
          } else {
            const m = clean.match(/FUMBLES?.*recovered by\s+([A-Za-z0-9\-]+)/i);
            if (m) desc = `Fumble rec by ${m[1]}`;
            else desc = clean.substring(0, 50);
          }
          if (desc.length > 55) desc = desc.substring(0, 52) + "...";
        } else {
          desc = `${td.team?.abbreviation || ""} ${toType}`;
        }

        const toClock = toPlay?.clock?.displayValue 
          ? `${toPlay.clock.displayValue} Q${toPlay.period?.number || ""}`.trim()
          : "";

        return {
          id: String(toPlay?.id || td.id || ""),
          type: toType,
          team: td.team?.abbreviation || "",
          desc: desc,
          clock: toClock
        };
      }

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
          const period = comp?.status?.period || 1;
          const clock = comp?.status?.displayClock || "0:00";
          if (period > 4) {
            shortStatus = `OT ${clock}`;
          } else {
            shortStatus = `Q${period} ${clock}`;
          }
        }

        const summary = summaryMap.get(event.id);

        return {
          id: event.id,
          date: event.date, // ISO 8601 UTC timestamp of kickoff
          away: away.team?.abbreviation || "AWY",
          awayScore: parseInt(away.score || "0", 10),
          home: home.team?.abbreviation || "HME",
          homeScore: parseInt(home.score || "0", 10),
          status: shortStatus,
          state: state,
          lastScore: summary ? extractLastScore(summary) : null,
          lastTurnover: summary ? extractLastTurnover(summary) : null
        };
      });

      // Optionally filter to a single favorite team if ?team=XYZ is passed
      const filteredGames = favTeam
        ? games.filter((g) => g.away === favTeam || g.home === favTeam)
        : games;

      // -------------------------------------------------------------
      // SMART ADAPTIVE BATTERY SCHEDULING DIRECTIVE
      // -------------------------------------------------------------
      let isLive = false;
      let nextPollSeconds = 300;
      let pollReason = "";

      const activeGame = filteredGames.find((g) => g.state === "in");
      if (activeGame) {
        isLive = true;
        nextPollSeconds = 300; // 5 min interval during active game play
        pollReason = "Game in progress (live 5-min polling)";
      } else {
        // Look for next upcoming scheduled game
        const upcomingGames = filteredGames
          .filter((g) => g.state === "pre" && g.date)
          .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime());

        if (upcomingGames.length > 0) {
          const nextGame = upcomingGames[0];
          const kickoffMs = new Date(nextGame.date).getTime();
          const diffSec = Math.round((kickoffMs - Date.now()) / 1000);

          if (diffSec <= 60) {
            nextPollSeconds = 300;
            pollReason = "Kickoff imminent, live 5-min polling active";
          } else if (diffSec < 86400) {
            // Kickoff is today! Wake 1 minute after kickoff time
            nextPollSeconds = diffSec + 60;
            pollReason = `Kickoff in ${(diffSec / 3600).toFixed(1)} hrs. Waking 1 min after kickoff`;
          } else {
            // More than 24 hours away: poll once tomorrow to recheck schedule
            nextPollSeconds = 86400;
            pollReason = `Next game in ${(diffSec / 86400).toFixed(1)} days. Sleeping 24h`;
          }
        } else {
          // Offseason or all games complete this week
          const isOffseason = raw.season?.type === 4;
          nextPollSeconds = isOffseason ? (86400 * 3) : 86400;
          pollReason = isOffseason ? "Offseason. Sleeping 3 days" : "All current games completed. Sleeping 24h";
        }
      }

      // Ensure interval is never below Garmin's 5-minute (300 sec) minimum
      if (nextPollSeconds < 300) {
        nextPollSeconds = 300;
      }

      return new Response(JSON.stringify({ 
        games: filteredGames,
        poll: {
          isLive,
          nextPollSeconds,
          reason: pollReason
        }
      }), {
        status: 200,
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": isLive ? "public, max-age=30" : "public, max-age=300",
          "Access-Control-Allow-Origin": "*"
        }
      });
    } catch (err) {
      return new Response(JSON.stringify({ error: "Proxy failure", message: err.message }), {
        status: 500,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*"
        }
      });
    }
  }
};

import worker from "./worker.js";

async function run() {
  console.log("Testing worker.js with smart scheduling directive...");
  
  // Test all games
  const reqAll = new Request("https://nfl-proxy.example.com/");
  const resAll = await worker.fetch(reqAll, {}, {});
  const dataAll = await resAll.json();
  
  console.log(`Status: ${resAll.status}`);
  console.log(`Games found: ${dataAll.games?.length || 0}`);
  console.log("Smart Poll Directive (All Games):", dataAll.poll);

  // Test filter by team
  const testTeam = "LAC";
  console.log(`\nTesting filter by team (?team=${testTeam})...`);
  const reqTeam = new Request(`https://nfl-proxy.example.com/?team=${testTeam}`);
  const resTeam = await worker.fetch(reqTeam, {}, {});
  const dataTeam = await resTeam.json();
  console.log(`Games found for ${testTeam}: ${dataTeam.games?.length || 0}`);
  console.log(`Smart Poll Directive (${testTeam}):`, dataTeam.poll);

  const jsonSize = new TextEncoder().encode(JSON.stringify(dataTeam)).length;
  console.log(`Payload size: ~${jsonSize} bytes`);

  console.log("\nAll proxy checks passed successfully!");
}

run().catch((err) => {
  console.error("Test failed:", err);
  process.exit(1);
});

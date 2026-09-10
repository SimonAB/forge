// Forge: create SP projects matching Finder / board folder titles.
const TITLES = [
  "0. DSEE Admin",
  "1. KRS",
  "2. Fundamentals of Programming",
  "3. Modern Inference",
  "Badgers_WT",
  "CDCS",
  "PGT",
  "Viruses-ViralHostPredictor"
];

async function run() {
  const existing = await PluginAPI.getAllProjects();
  const have = new Set((existing || []).map((p) => p.title));
  let created = 0;
  let skipped = 0;
  const errors = [];
  for (const title of TITLES) {
    if (have.has(title)) {
      skipped += 1;
      continue;
    }
    try {
      await PluginAPI.addProject({ title });
      have.add(title);
      created += 1;
    } catch (err) {
      errors.push(title + ': ' + (err && err.message ? err.message : String(err)));
    }
  }
  await PluginAPI.persistDataSynced(
    JSON.stringify({
      completedAt: new Date().toISOString(),
      created,
      skipped,
      errors,
      titles: TITLES,
    }),
  );
  const msg =
    'Finder→SP: created ' +
    created +
    ' project(s), skipped ' +
    skipped +
    (errors.length ? ', errors ' + errors.length : '');
  console.log(msg, errors);
  PluginAPI.showSnack({
    msg,
    type: errors.length ? 'ERROR' : 'SUCCESS',
  });
}

run().catch((err) => {
  console.error('forge-finder-projects failed', err);
  PluginAPI.showSnack({
    msg: 'Finder projects failed: ' + (err && err.message ? err.message : String(err)),
    type: 'ERROR',
  });
});

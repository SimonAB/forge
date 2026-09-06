// Forge one-shot: create missing SP projects for Forge board folders.
const TITLES = [
  "Badgers 2"
];

async function alreadyDone() {
  try {
    const raw = await PluginAPI.loadSyncedData();
    if (!raw) return false;
    const parsed = JSON.parse(raw);
    return Boolean(parsed && parsed.completedAt);
  } catch (e) {
    return false;
  }
}

async function run() {
  if (await alreadyDone()) {
    console.log('forge-bulk-projects: already completed; skip');
    return;
  }
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
    }),
  );
  const msg =
    'Forge: created ' +
    created +
    ' SP project(s), skipped ' +
    skipped +
    (errors.length ? ', errors ' + errors.length : '');
  console.log(msg, errors);
  PluginAPI.showSnack({
    msg,
    type: errors.length ? 'ERROR' : 'SUCCESS',
  });
}

run().catch((err) => {
  console.error('forge-bulk-projects failed', err);
  PluginAPI.showSnack({
    msg: 'Forge bulk projects failed: ' + (err && err.message ? err.message : String(err)),
    type: 'ERROR',
  });
});

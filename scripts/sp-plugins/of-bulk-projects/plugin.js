const TITLES = ["PGT"];
async function run() {
  const existing = await PluginAPI.getAllProjects();
  const have = new Set((existing || []).map((p) => p.title));
  let created=0, skipped=0; const errors=[];
  for (const title of TITLES) {
    if (have.has(title)) { skipped++; continue; }
    try { await PluginAPI.addProject({ title }); have.add(title); created++; }
    catch (err) { errors.push(String(err && err.message || err)); }
  }
  await PluginAPI.persistDataSynced(JSON.stringify({completedAt:new Date().toISOString(),created,skipped,errors}));
  PluginAPI.showSnack({msg:'OF→SP: created '+created+' (PGT)', type: errors.length?'ERROR':'SUCCESS'});
}
run().catch(e=>PluginAPI.showSnack({msg:String(e),type:'ERROR'}));

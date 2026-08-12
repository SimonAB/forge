import Foundation

/// OmniJS function sources evaluated inside OmniFocus (return JSON strings).
///
/// Link-root arguments: `args.linkRoot` (canonical, default 🔥 Forge) and
/// `args.legacyRoots` (extra root names still recognised when reading).
/// Column-root arguments: `args.columnRoot` (nested fallback, default KanbanStatus),
/// `args.legacyColumnRoots`, `args.columnAliases`, `args.columnAliasReads`, and
/// `args.flatColumnTags` (prefer flat aliases when true).
public enum OmniJSSnippets {
    /// Export Forge link tags, linked active tasks, and OF project names.
    public static let exportInventory = #"""
function(args) {
  var linkRoot = (args && args.linkRoot) ? args.linkRoot : "🔥 Forge";
  var legacyRoots = (args && args.legacyRoots) ? args.legacyRoots : ["Forge"];
  var columnRoot = (args && args.columnRoot) ? args.columnRoot : "KanbanStatus";
  var legacyColumnRoots = (args && args.legacyColumnRoots) ? args.legacyColumnRoots : ["ForgeColumn"];
  var columnAliases = (args && args.columnAliases) ? args.columnAliases : {};
  var columnAliasReads = (args && args.columnAliasReads) ? args.columnAliasReads : {};
  var allRoots = [linkRoot];
  for (var ri = 0; ri < legacyRoots.length; ri++) {
    if (legacyRoots[ri] && legacyRoots[ri] !== linkRoot) allRoots.push(legacyRoots[ri]);
  }
  var allColumnRoots = [columnRoot];
  for (var cri = 0; cri < legacyColumnRoots.length; cri++) {
    if (legacyColumnRoots[cri] && legacyColumnRoots[cri] !== columnRoot) {
      allColumnRoots.push(legacyColumnRoots[cri]);
    }
  }
  var aliasNameToColumn = {};
  for (var rk in columnAliasReads) {
    if (Object.prototype.hasOwnProperty.call(columnAliasReads, rk) && columnAliasReads[rk]) {
      aliasNameToColumn[rk] = columnAliasReads[rk];
    }
  }
  for (var ak in columnAliases) {
    if (Object.prototype.hasOwnProperty.call(columnAliases, ak) && columnAliases[ak]) {
      aliasNameToColumn[columnAliases[ak]] = ak;
    }
  }
  function isRootName(name) {
    for (var i = 0; i < allRoots.length; i++) {
      if (allRoots[i] === name) return true;
    }
    return false;
  }
  function isColumnRootName(name) {
    for (var i = 0; i < allColumnRoots.length; i++) {
      if (allColumnRoots[i] === name) return true;
    }
    return false;
  }
  function tagPathComponents(tag) {
    var parts = [];
    var current = tag;
    while (current) {
      parts.unshift((current.name || "").trim());
      current = current.parent;
    }
    return parts.filter(function(p) { return p.length > 0; });
  }
  function tagPathString(tag) {
    return tagPathComponents(tag).join(":");
  }
  function folderFromForgeTag(tag) {
    var comps = tagPathComponents(tag);
    if (comps.length >= 2 && isRootName(comps[0])) {
      return { path: tagPathString(tag), folder: comps[comps.length - 1] };
    }
    var flat = (tag.name || "").trim();
    for (var i = 0; i < allRoots.length; i++) {
      var prefix = allRoots[i] + "/";
      if (flat.indexOf(prefix) === 0 && flat.length > prefix.length) {
        return { path: flat, folder: flat.slice(prefix.length) };
      }
    }
    return null;
  }
  function columnInfoFromTask(task) {
    var columns = [];
    var aliasName = null;
    var nestedRoot = null;
    function pushColumn(col) {
      if (!col) return;
      for (var i = 0; i < columns.length; i++) {
        if (columns[i] === col) return;
      }
      columns.push(col);
    }
    var tags = task.tags || [];
    for (var i = 0; i < tags.length; i++) {
      var n = (tags[i].name || "").trim();
      if (aliasNameToColumn[n]) {
        pushColumn(aliasNameToColumn[n]);
        if (!aliasName) aliasName = n;
      }
      var comps = tagPathComponents(tags[i]);
      if (comps.length >= 2 && isColumnRootName(comps[0])) {
        pushColumn(comps[1]);
        if (!nestedRoot) nestedRoot = comps[0];
      } else {
        for (var ci = 0; ci < allColumnRoots.length; ci++) {
          var cprefix = allColumnRoots[ci] + "/";
          if (n.indexOf(cprefix) === 0) {
            pushColumn(n.slice(cprefix.length));
            if (!nestedRoot) nestedRoot = allColumnRoots[ci];
            break;
          }
        }
      }
    }
    return {
      columns: columns,
      column: columns.length ? columns[0] : null,
      root: nestedRoot,
      alias: aliasName,
      ambiguous: columns.length > 1
    };
  }
  function firstForgeLink(task) {
    var tags = task.tags || [];
    for (var i = 0; i < tags.length; i++) {
      var info = folderFromForgeTag(tags[i]);
      if (info) return info;
    }
    return null;
  }

  var hasForgeRoot = false;
  var hasCanonicalRoot = false;
  var linkMap = {};
  var allTags = flattenedTags;
  for (var ti = 0; ti < allTags.length; ti++) {
    var t = allTags[ti];
    var comps = tagPathComponents(t);
    if (comps.length === 1 && isRootName(comps[0])) {
      hasForgeRoot = true;
      if (comps[0] === linkRoot) hasCanonicalRoot = true;
    }
    var info = folderFromForgeTag(t);
    if (info) {
      if (!linkMap[info.path]) {
        linkMap[info.path] = { path: info.path, folderName: info.folder, taskCount: 0 };
      }
    }
  }

  var tasksOut = [];
  var taskList = flattenedTasks;
  for (var i = 0; i < taskList.length; i++) {
    var task = taskList[i];
    if (task.completed) continue;
    if (task.effectiveActive === false) continue;
    var link = firstForgeLink(task);
    if (!link) continue;
    if (linkMap[link.path]) {
      linkMap[link.path].taskCount += 1;
    } else {
      linkMap[link.path] = { path: link.path, folderName: link.folder, taskCount: 1 };
    }
    var due = task.dueDate || null;
    var colInfo = columnInfoFromTask(task);
    tasksOut.push({
      id: String(task.id.primaryKey),
      title: task.name || "Untitled",
      projectFolderName: link.folder,
      projectTag: link.path,
      forgeColumn: colInfo.column,
      forgeColumns: colInfo.columns,
      columnTagRoot: colInfo.root,
      columnAliasTag: colInfo.alias,
      columnAmbiguous: colInfo.ambiguous,
      due: due ? due.toISOString() : null,
      completed: false,
      ofProjectName: task.containingProject ? (task.containingProject.name || null) : null
    });
  }

  var linkTags = [];
  for (var k in linkMap) {
    if (Object.prototype.hasOwnProperty.call(linkMap, k)) {
      linkTags.push(linkMap[k]);
    }
  }

  var ofProjectNames = [];
  var ofProjectSummaries = [];
  var projects = flattenedProjects;
  for (var pi = 0; pi < projects.length; pi++) {
    var proj = projects[pi];
    var pn = (proj.name || "").trim();
    if (!pn) continue;
    ofProjectNames.push(pn);
    var activeCount = 0;
    var ptasks = proj.flattenedTasks || [];
    for (var pti = 0; pti < ptasks.length; pti++) {
      var pt = ptasks[pti];
      if (pt.completed) continue;
      if (pt.effectiveActive === false) continue;
      activeCount += 1;
    }
    var isCompleted = false;
    try {
      if (typeof Project !== "undefined" && Project.Status) {
        isCompleted = (proj.status === Project.Status.Done || proj.status === Project.Status.Dropped);
      }
    } catch (e) {}
    ofProjectSummaries.push({ name: pn, activeTaskCount: activeCount, isCompleted: isCompleted });
  }

  return JSON.stringify({
    ok: true,
    generatedAt: new Date().toISOString(),
    hasForgeRootTag: hasForgeRoot,
    hasCanonicalRootTag: hasCanonicalRoot,
    linkRoot: linkRoot,
    columnRoot: columnRoot,
    linkTags: linkTags,
    tasks: tasksOut,
    ofProjectNames: ofProjectNames,
    ofProjectSummaries: ofProjectSummaries
  });
}
"""#

    /// Create link root and/or `<root>:<folder>` tags.
    /// Args: `{ ensureRoot, folders, linkRoot }`
    public static let ensureLinkTags = #"""
function(args) {
  var linkRoot = (args && args.linkRoot) ? args.linkRoot : "🔥 Forge";
  var created = [];
  var root = null;
  var tags = flattenedTags;
  for (var i = 0; i < tags.length; i++) {
    if (!tags[i].parent && (tags[i].name || "") === linkRoot) {
      root = tags[i];
      break;
    }
  }
  if (args.ensureRoot) {
    if (!root) {
      root = new Tag(linkRoot);
      created.push(linkRoot);
    }
  }
  var folders = args.folders || [];
  for (var fi = 0; fi < folders.length; fi++) {
    var name = folders[fi];
    if (!name) continue;
    if (!root) {
      root = new Tag(linkRoot);
      created.push(linkRoot);
    }
    var existing = null;
    var kids = root.children || [];
    for (var ki = 0; ki < kids.length; ki++) {
      if ((kids[ki].name || "") === name) { existing = kids[ki]; break; }
    }
    if (!existing) {
      new Tag(name, root);
      created.push(linkRoot + ":" + name);
    }
  }
  return JSON.stringify({ ok: true, created: created });
}
"""#

    /// Set column tags on linked tasks (flat aliases and/or nested column root).
    /// Args: single `{ folderName, column, taskIds? … }` or batch `{ updates: [{folderName,column,taskIds?}], … }`.
    public static let setForgeColumnTags = #"""
function(args) {
  var linkRoot = (args && args.linkRoot) ? args.linkRoot : "🔥 Forge";
  var legacyRoots = (args && args.legacyRoots) ? args.legacyRoots : ["Forge"];
  var columnRoot = (args && args.columnRoot) ? args.columnRoot : "KanbanStatus";
  var legacyColumnRoots = (args && args.legacyColumnRoots) ? args.legacyColumnRoots : ["ForgeColumn"];
  var columnAliases = (args && args.columnAliases) ? args.columnAliases : {};
  var columnAliasReads = (args && args.columnAliasReads) ? args.columnAliasReads : {};
  var flatColumnTags = !(args && args.flatColumnTags === false);
  var allRoots = [linkRoot];
  for (var ri = 0; ri < legacyRoots.length; ri++) {
    if (legacyRoots[ri] && legacyRoots[ri] !== linkRoot) allRoots.push(legacyRoots[ri]);
  }
  var allColumnRoots = [columnRoot];
  for (var cri = 0; cri < legacyColumnRoots.length; cri++) {
    if (legacyColumnRoots[cri] && legacyColumnRoots[cri] !== columnRoot) {
      allColumnRoots.push(legacyColumnRoots[cri]);
    }
  }
  var allAliasNames = [];
  for (var rk in columnAliasReads) {
    if (Object.prototype.hasOwnProperty.call(columnAliasReads, rk) && columnAliasReads[rk]) {
      allAliasNames.push(rk);
    }
  }
  for (var ak in columnAliases) {
    if (Object.prototype.hasOwnProperty.call(columnAliases, ak) && columnAliases[ak]) {
      if (allAliasNames.indexOf(columnAliases[ak]) < 0) allAliasNames.push(columnAliases[ak]);
    }
  }
  function isRootName(name) {
    for (var i = 0; i < allRoots.length; i++) {
      if (allRoots[i] === name) return true;
    }
    return false;
  }
  function isColumnRootName(name) {
    for (var i = 0; i < allColumnRoots.length; i++) {
      if (allColumnRoots[i] === name) return true;
    }
    return false;
  }
  function isAliasName(name) {
    for (var i = 0; i < allAliasNames.length; i++) {
      if (allAliasNames[i] === name) return true;
    }
    return false;
  }
  function tagPathComponents(tag) {
    var parts = [];
    var current = tag;
    while (current) {
      parts.unshift((current.name || "").trim());
      current = current.parent;
    }
    return parts.filter(function(p) { return p.length > 0; });
  }
  function folderFromForgeTag(tag) {
    var comps = tagPathComponents(tag);
    if (comps.length >= 2 && isRootName(comps[0])) {
      return comps[comps.length - 1];
    }
    var flat = (tag.name || "").trim();
    for (var i = 0; i < allRoots.length; i++) {
      var prefix = allRoots[i] + "/";
      if (flat.indexOf(prefix) === 0) return flat.slice(prefix.length);
    }
    return null;
  }
  var columnTagCache = {};
  function findOrCreateColumnTag(column) {
    if (columnTagCache[column]) return columnTagCache[column];
    var root = null;
    var tags = flattenedTags;
    for (var i = 0; i < tags.length; i++) {
      if (!tags[i].parent && (tags[i].name || "") === columnRoot) {
        root = tags[i];
        break;
      }
    }
    if (!root) root = new Tag(columnRoot);
    var kids = root.children || [];
    for (var k = 0; k < kids.length; k++) {
      if ((kids[k].name || "") === column) {
        columnTagCache[column] = kids[k];
        return kids[k];
      }
    }
    var created = new Tag(column, root);
    columnTagCache[column] = created;
    return created;
  }
  var aliasTagCache = {};
  function findExistingTagByName(name) {
    if (!name) return null;
    if (Object.prototype.hasOwnProperty.call(aliasTagCache, name)) return aliasTagCache[name];
    var tags = flattenedTags;
    var nested = null;
    for (var i = 0; i < tags.length; i++) {
      if ((tags[i].name || "").trim() !== name) continue;
      if (!tags[i].parent) {
        aliasTagCache[name] = tags[i];
        return tags[i];
      }
      if (!nested) nested = tags[i];
    }
    aliasTagCache[name] = nested;
    return nested;
  }
  function findOrCreateFlatTag(name) {
    var existing = findExistingTagByName(name);
    if (existing) return existing;
    var created = new Tag(name);
    aliasTagCache[name] = created;
    return created;
  }
  function removeColumnTags(task) {
    var tags = (task.tags || []).slice();
    for (var i = 0; i < tags.length; i++) {
      var comps = tagPathComponents(tags[i]);
      if (comps.length >= 1 && isColumnRootName(comps[0])) {
        task.removeTag(tags[i]);
      } else if (isAliasName((tags[i].name || "").trim())) {
        task.removeTag(tags[i]);
      }
    }
  }
  function taskById(id) {
    try {
      if (typeof Task !== "undefined" && Task.byIdentifier) {
        var t = Task.byIdentifier(String(id));
        if (t) return t;
      }
    } catch (e) {}
    return null;
  }
  function applyOne(folderName, column, onlyIds) {
    var idSet = null;
    var idList = onlyIds || null;
    if (idList && idList.length) {
      idSet = {};
      for (var x = 0; x < idList.length; x++) idSet[String(idList[x])] = true;
    }
    var aliasName = columnAliases[column] || null;
    var useFlat = flatColumnTags && !!aliasName;
    var aliasTag = null;
    var columnTag = null;
    var missingAlias = [];
    if (aliasName) {
      aliasTag = useFlat ? findOrCreateFlatTag(aliasName) : findExistingTagByName(aliasName);
      if (!aliasTag && missingAlias.indexOf(aliasName) < 0) missingAlias.push(aliasName);
    }
    if (!useFlat) {
      columnTag = findOrCreateColumnTag(column);
    }
    var updated = [];

    function applyToTask(task) {
      removeColumnTags(task);
      if (useFlat && aliasTag) {
        task.addTag(aliasTag);
      } else {
        if (columnTag) task.addTag(columnTag);
        if (aliasTag) task.addTag(aliasTag);
      }
      updated.push(String(task.id.primaryKey));
    }

    if (idList && idList.length && typeof Task !== "undefined" && Task.byIdentifier) {
      for (var ii = 0; ii < idList.length; ii++) {
        var task = taskById(idList[ii]);
        if (!task || task.completed) continue;
        applyToTask(task);
      }
      return { folderName: folderName, column: column, updated: updated, missingAlias: missingAlias };
    }

    var taskList = flattenedTasks;
    for (var i = 0; i < taskList.length; i++) {
      var task = taskList[i];
      if (task.completed) continue;
      var tid = String(task.id.primaryKey);
      if (idSet && !idSet[tid]) continue;
      var tags = task.tags || [];
      var match = false;
      for (var t = 0; t < tags.length; t++) {
        if (folderFromForgeTag(tags[t]) === folderName) { match = true; break; }
      }
      if (!match) continue;
      applyToTask(task);
    }
    return { folderName: folderName, column: column, updated: updated, missingAlias: missingAlias };
  }

  var updates = (args && args.updates) ? args.updates : null;
  if (!updates || !updates.length) {
    updates = [{ folderName: args.folderName, column: args.column, taskIds: args.taskIds || [] }];
  }
  var results = [];
  var allUpdated = [];
  var allMissing = [];
  for (var u = 0; u < updates.length; u++) {
    var item = updates[u];
    if (!item || !item.folderName || !item.column) continue;
    var one = applyOne(item.folderName, item.column, item.taskIds || []);
    results.push(one);
    for (var ui = 0; ui < one.updated.length; ui++) allUpdated.push(one.updated[ui]);
    for (var mi = 0; mi < one.missingAlias.length; mi++) {
      if (allMissing.indexOf(one.missingAlias[mi]) < 0) allMissing.push(one.missingAlias[mi]);
    }
  }
  return JSON.stringify({
    ok: true,
    updated: allUpdated,
    missingAlias: allMissing,
    columnRoot: columnRoot,
    flatColumnTags: flatColumnTags,
    results: results
  });
}
"""#

    /// Ensure `<linkRoot>:<folderName>` exists; tag matching OF project + active tasks.
    /// Args: `{ folderName, linkRoot, aliasProjectNames? }`
    public static let tagMatchingOfProject = #"""
function(args) {
  var linkRoot = (args && args.linkRoot) ? args.linkRoot : "🔥 Forge";
  var folderName = args.folderName;
  var aliasProjectNames = (args && args.aliasProjectNames) ? args.aliasProjectNames : [];
  if (!folderName) {
    return JSON.stringify({ ok: false, error: "folderName required" });
  }

  var root = null;
  var tags = flattenedTags;
  for (var i = 0; i < tags.length; i++) {
    if (!tags[i].parent && (tags[i].name || "") === linkRoot) {
      root = tags[i];
      break;
    }
  }
  var createdTag = false;
  if (!root) {
    root = new Tag(linkRoot);
    createdTag = true;
  }
  var linkTag = null;
  var kids = root.children || [];
  for (var k = 0; k < kids.length; k++) {
    if ((kids[k].name || "") === folderName) {
      linkTag = kids[k];
      break;
    }
  }
  if (!linkTag) {
    linkTag = new Tag(folderName, root);
    createdTag = true;
  }

  var projectNamesToTry = [folderName];
  for (var ai = 0; ai < aliasProjectNames.length; ai++) {
    var aliasName = (aliasProjectNames[ai] || "").trim();
    if (!aliasName) continue;
    var seen = false;
    for (var si = 0; si < projectNamesToTry.length; si++) {
      if (projectNamesToTry[si] === aliasName) { seen = true; break; }
    }
    if (!seen) projectNamesToTry.push(aliasName);
  }
  var project = null;
  var matchedProjectName = null;
  var projects = flattenedProjects;
  for (var ni = 0; ni < projectNamesToTry.length; ni++) {
    var targetName = projectNamesToTry[ni];
    for (var pi = 0; pi < projects.length; pi++) {
      if ((projects[pi].name || "").trim() === targetName) {
        project = projects[pi];
        matchedProjectName = targetName;
        break;
      }
    }
    if (project) break;
  }
  if (!project) {
    return JSON.stringify({
      ok: false,
      error: "No OmniFocus project named " + projectNamesToTry.join(", "),
      createdTag: createdTag
    });
  }

  var taggedProject = false;
  try {
    if (typeof project.addTag === "function") {
      project.addTag(linkTag);
      taggedProject = true;
    }
  } catch (e) {}

  var taggedTaskIds = [];
  var ptasks = project.flattenedTasks || [];
  for (var ti = 0; ti < ptasks.length; ti++) {
    var task = ptasks[ti];
    if (task.completed) continue;
    if (task.effectiveActive === false) continue;
    var already = false;
    var ttags = task.tags || [];
    for (var tt = 0; tt < ttags.length; tt++) {
      if (ttags[tt] === linkTag) { already = true; break; }
      var p = ttags[tt].parent;
      if (p && (p.name || "") === linkRoot && (ttags[tt].name || "") === folderName) {
        already = true;
        break;
      }
    }
    if (!already) {
      task.addTag(linkTag);
    }
    taggedTaskIds.push(String(task.id.primaryKey));
  }

  return JSON.stringify({
    ok: true,
    createdTag: createdTag,
    taggedProject: taggedProject,
    taggedTaskIds: taggedTaskIds,
    tagPath: linkRoot + ":" + folderName
  });
}
"""#

    /// Set OF project status by name (and optional aliases).
    /// Args: `{ folderName, status: "Active"|"Done", aliasProjectNames? }`
    public static let setOfProjectStatus = #"""
function(args) {
  var folderName = args && args.folderName;
  var statusName = (args && args.status) ? String(args.status) : "";
  var aliasProjectNames = (args && args.aliasProjectNames) ? args.aliasProjectNames : [];
  if (!folderName) {
    return JSON.stringify({ ok: false, error: "folderName required" });
  }
  if (statusName !== "Active" && statusName !== "Done") {
    return JSON.stringify({ ok: false, error: "status must be Active or Done" });
  }
  if (typeof Project === "undefined" || !Project.Status) {
    return JSON.stringify({ ok: false, error: "Project.Status unavailable" });
  }

  var names = [folderName];
  for (var a = 0; a < aliasProjectNames.length; a++) {
    var an = aliasProjectNames[a];
    if (an && names.indexOf(an) < 0) names.push(an);
  }

  var projects = flattenedProjects;
  var match = null;
  for (var i = 0; i < projects.length; i++) {
    var p = projects[i];
    var n = (p.name || "");
    for (var j = 0; j < names.length; j++) {
      if (n === names[j]) { match = p; break; }
    }
    if (match) break;
  }
  if (!match) {
    return JSON.stringify({
      ok: true,
      updated: false,
      reason: "no_matching_project",
      folderName: folderName,
      status: statusName
    });
  }

  var before = "unknown";
  try {
    if (match.status === Project.Status.Done) before = "Done";
    else if (match.status === Project.Status.Dropped) before = "Dropped";
    else if (match.status === Project.Status.OnHold) before = "OnHold";
    else if (match.status === Project.Status.Active) before = "Active";
  } catch (e) {}

  var target = (statusName === "Done") ? Project.Status.Done : Project.Status.Active;
  if (match.status === target) {
    return JSON.stringify({
      ok: true,
      updated: false,
      reason: "already_set",
      folderName: folderName,
      projectName: match.name || folderName,
      status: statusName,
      before: before
    });
  }

  match.status = target;
  return JSON.stringify({
    ok: true,
    updated: true,
    folderName: folderName,
    projectName: match.name || folderName,
    status: statusName,
    before: before
  });
}
"""#
}

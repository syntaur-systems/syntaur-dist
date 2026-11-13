use serde_json::{Map, Value};
use std::collections::{BTreeMap, BTreeSet};
use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::Path;

const RAW_LIMIT: u64 = 32 * 1024 * 1024;
const RELEASE_LIMIT: usize = 16 * 1024 * 1024;
type Result<T> = std::result::Result<T, String>;
type IdMap = BTreeMap<String, String>;

fn object(v: &mut Value) -> Result<&mut Map<String, Value>> {
    v.as_object_mut().ok_or_else(|| "expected object".into())
}
fn array(v: &mut Value) -> Result<&mut Vec<Value>> {
    v.as_array_mut().ok_or_else(|| "expected array".into())
}
fn remap(v: &mut Value, ids: &IdMap) -> Result<()> {
    let id = v.as_str().ok_or("non-string reference")?;
    if let Some(new) = ids.get(id) {
        *v = Value::String(new.clone());
    } else {
        return Err("unresolved or external reference".into());
    }
    Ok(())
}
fn field(o: &mut Map<String, Value>, name: &str, ids: &IdMap) -> Result<()> {
    remap(o.get_mut(name).ok_or("missing reference")?, ids)
}
fn refs(o: &mut Map<String, Value>, name: &str, ids: &IdMap) -> Result<()> {
    if let Some(v) = o.get_mut(name) {
        for v in array(v)? {
            remap(v, ids)?;
        }
    }
    Ok(())
}
fn rewrite(d: &mut Value, ids: &IdMap) -> Result<()> {
    let root = object(d)?;
    field(root, "SPDXID", ids)?;
    refs(root, "documentDescribes", ids)?;
    for (kind, links) in [("packages", "hasFiles"), ("files", "fileDependencies")] {
        if let Some(nodes) = root.get_mut(kind) {
            for node in array(nodes)? {
                let node = object(node)?;
                field(node, "SPDXID", ids)?;
                refs(node, links, ids)?;
            }
        }
    }
    if let Some(nodes) = root.get_mut("snippets") {
        for node in array(nodes)? {
            let node = object(node)?;
            field(node, "SPDXID", ids)?;
            field(node, "snippetFromFile", ids)?;
            for range in array(node.get_mut("ranges").ok_or("missing snippet ranges")?)? {
                let range = object(range)?;
                for name in ["startPointer", "endPointer"] {
                    field(
                        object(range.get_mut(name).ok_or("missing pointer")?)?,
                        "reference",
                        ids,
                    )?;
                }
            }
        }
    }
    if let Some(edges) = root.get_mut("relationships") {
        for edge in array(edges)? {
            let edge = object(edge)?;
            field(edge, "spdxElementId", ids)?;
            let target = edge
                .get_mut("relatedSpdxElement")
                .ok_or("missing reference")?;
            if !matches!(target.as_str(), Some("NONE" | "NOASSERTION")) {
                remap(target, ids)?;
            }
        }
    }
    Ok(())
}
fn normalize(raw: &[u8]) -> Result<Vec<u8>> {
    if raw.is_empty() || raw.len() as u64 > RAW_LIMIT {
        return Err("raw staging limit".into());
    }
    // arbitrary_precision retains integers/decimals exactly, including >2^53.
    // from_slice also rejects a stream containing more than one JSON document.
    let original: Value = serde_json::from_slice(raw).map_err(|e| e.to_string())?;
    if original.get("spdxVersion").and_then(Value::as_str) != Some("SPDX-2.3")
        || original.get("SPDXID").and_then(Value::as_str) != Some("SPDXRef-DOCUMENT")
        || !original.get("packages").is_some_and(Value::is_array)
    {
        return Err("unsupported document shape".into());
    }
    if let Some(external) = original.get("externalDocumentRefs")
        && !external.as_array().is_some_and(Vec::is_empty)
    {
        return Err("external document references unsupported".into());
    }
    let mut declared = BTreeSet::new();
    let mut add = |v: &Value| -> Result<()> {
        let id = v
            .get("SPDXID")
            .and_then(Value::as_str)
            .ok_or("missing node ID")?;
        let suffix = id.strip_prefix("SPDXRef-").ok_or("invalid node ID")?;
        if suffix.is_empty()
            || !suffix
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || c == b'.' || c == b'-')
        {
            return Err("invalid node ID".into());
        }
        if !declared.insert(id.to_owned()) {
            return Err("duplicate node ID".into());
        }
        Ok(())
    };
    add(&original)?;
    for kind in ["packages", "files", "snippets"] {
        if let Some(nodes) = original.get(kind) {
            for node in nodes.as_array().ok_or("expected node array")? {
                add(node)?;
            }
        }
    }
    let mut forward = IdMap::new();
    forward.insert("SPDXRef-DOCUMENT".into(), "SPDXRef-DOCUMENT".into());
    for (index, old) in declared
        .into_iter()
        .filter(|v| v != "SPDXRef-DOCUMENT")
        .enumerate()
    {
        forward.insert(old, format!("SPDXRef-{index}"));
    }
    let reverse: IdMap = forward
        .iter()
        .map(|(a, b)| (b.clone(), a.clone()))
        .collect();
    if reverse.len() != forward.len() {
        return Err("identifier collision".into());
    }
    let mut normalized = original.clone();
    rewrite(&mut normalized, &forward)?;
    let mut restored = normalized.clone();
    rewrite(&mut restored, &reverse)?;
    if restored != original {
        return Err("round-trip graph or metadata changed".into());
    }
    let mut out = serde_json::to_vec(&normalized).map_err(|e| e.to_string())?;
    out.push(b'\n');
    if out.len() > RELEASE_LIMIT {
        return Err("unchanged 16 MiB release limit exceeded".into());
    }
    Ok(out)
}
fn process(path: &Path) -> Result<()> {
    let metadata = fs::symlink_metadata(path).map_err(|e| e.to_string())?;
    if !metadata.file_type().is_file() {
        return Err("input must be a regular non-symlink file".into());
    }
    if metadata.len() == 0 || metadata.len() > RAW_LIMIT {
        return Err("raw staging limit".into());
    }
    let mut raw = Vec::new();
    File::open(path)
        .map_err(|e| e.to_string())?
        .take(RAW_LIMIT + 1)
        .read_to_end(&mut raw)
        .map_err(|e| e.to_string())?;
    let output = normalize(&raw)?;
    // Adjacent tempfile guarantees same-filesystem atomic replacement.
    // No destination mutation occurs until all validation is complete.
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let mut temp = tempfile::NamedTempFile::new_in(parent).map_err(|e| e.to_string())?;
    temp.write_all(&output).map_err(|e| e.to_string())?;
    temp.as_file().sync_all().map_err(|e| e.to_string())?;
    temp.persist(path).map_err(|e| e.to_string())?;
    Ok(())
}
fn main() {
    let args: Vec<_> = std::env::args_os().collect();
    if args.len() != 2 {
        eprintln!("usage: syntaur-sbom-normalize SPDX_JSON");
        std::process::exit(2);
    }
    if let Err(e) = process(Path::new(&args[1])) {
        eprintln!("invalid dependency SBOM: {e}");
        std::process::exit(1);
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn numbers_and_metadata_are_exact() {
        let raw = br#"{"spdxVersion":"SPDX-2.3","SPDXID":"SPDXRef-DOCUMENT","packages":[{"SPDXID":"SPDXRef-long","name":"SPDXRef-long","big":9007199254740993,"precise":1.12345678901234567890123456789}],"relationships":[{"spdxElementId":"SPDXRef-long","relatedSpdxElement":"NONE"}]}"#;
        let out = normalize(raw).unwrap();
        let text = String::from_utf8(out).unwrap();
        assert!(text.contains("9007199254740993"));
        assert!(text.contains("1.12345678901234567890123456789"));
        assert!(text.contains("\"name\":\"SPDXRef-long\""));
        assert!(text.contains("\"SPDXID\":\"SPDXRef-0\""));
    }
    #[test]
    fn rejects_stream_and_duplicate_ids() {
        assert!(normalize(br#"{} {}"#).is_err());
        assert!(normalize(br#"{"spdxVersion":"SPDX-2.3","SPDXID":"SPDXRef-DOCUMENT","packages":[{"SPDXID":"SPDXRef-DOCUMENT"}]}"#).is_err());
    }
    #[test]
    fn preserves_file_on_failure_and_atomically_replaces_on_success() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("sbom.json");
        fs::write(&path, b"invalid").unwrap();
        assert!(process(&path).is_err());
        assert_eq!(fs::read(&path).unwrap(), b"invalid");
        fs::write(
            &path,
            br#"{"spdxVersion":"SPDX-2.3","SPDXID":"SPDXRef-DOCUMENT","packages":[]}"#,
        )
        .unwrap();
        process(&path).unwrap();
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 1);
    }
}

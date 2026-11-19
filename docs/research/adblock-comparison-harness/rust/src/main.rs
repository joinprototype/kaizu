use adblock::content_blocking::{CbRule, CbRuleCreationFailure, CbRuleEquivalent};
use adblock::lists::{parse_filter, FilterSet, ParseOptions, ParsedLine};
use adblock::request::Request;
use adblock::Engine;
use std::convert::TryInto;
use std::io::Write;

fn reason(e: &CbRuleCreationFailure) -> String {
    format!("{:?}", e).split('(').next().unwrap().to_string()
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args[1].as_str() {
        // convert <out.json> <lines.tsv> <list>...
        "convert" => {
            let out = &args[2];
            let mut tsvf = std::fs::File::create(&args[3]).unwrap();
            let mut set = FilterSet::new(true);
            for path in &args[4..] {
                let text = std::fs::read_to_string(path).unwrap();
                let name = std::path::Path::new(path).file_name().unwrap().to_string_lossy().to_string();
                for line in text.lines() {
                    let t = line.trim();
                    if t.is_empty() || t.starts_with('!') || t.starts_with("[Adblock") {
                        continue;
                    }
                    let (status, why) = match parse_filter(line, true, ParseOptions::default()) {
                        Err(e) => ("parse-fail".to_string(), format!("{:?}", e)),
                        Ok(ParsedLine::Network(f)) => match TryInto::<CbRuleEquivalent>::try_into(f) {
                            Ok(_) => ("ok".into(), "".into()),
                            Err(e) => ("skip".into(), reason(&e)),
                        },
                        Ok(ParsedLine::Cosmetic(f)) => match TryInto::<CbRule>::try_into(f) {
                            Ok(_) => ("ok".into(), "".into()),
                            Err(e) => ("skip".into(), reason(&e)),
                        },
                    };
                    writeln!(tsvf, "{}\t{}\t{}\t{}", name, status, why, line.replace('\t', " ")).unwrap();
                }
                set.add_filter_list(text.clone(), ParseOptions::default());
            }
            let (rules, used) = set.into_content_blocking().unwrap();
            std::fs::write(out, serde_json::to_string(&rules).unwrap()).unwrap();
            eprintln!("brave rules={} filters_used={}", rules.len(), used.len());
        }
        // engine <urls.tsv> <list>...   urls: url \t source \t type -> block/allow per line
        "engine" => {
            let mut set = FilterSet::new(false);
            for path in &args[3..] {
                set.add_filter_list(std::fs::read_to_string(path).unwrap(), ParseOptions::default());
            }
            let engine = Engine::new_with_filter_set(set);
            let text = std::fs::read_to_string(&args[2]).unwrap();
            for line in text.lines() {
                let p: Vec<&str> = line.split('\t').collect();
                match Request::new(p[0], p[1], p[2], "") {
                    Ok(r) => {
                        let res = engine.check_network_request(&r);
                        println!("{}", if res.filter.is_some() && res.exception.is_none() { "block" } else { "allow" });
                    }
                    Err(_) => println!("error"),
                }
            }
        }
        _ => panic!(),
    }
}

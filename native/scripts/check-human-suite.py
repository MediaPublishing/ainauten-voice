#!/usr/bin/env python3
"""Audit pinned public FLEURS results without models, user data or uploads.

Finite literal checks are not a semantic-equivalence or end-to-end acceptance proof.
Number aliases affect only this separate check, never the reported strict WER.
"""
import argparse
from collections import Counter, defaultdict
import difflib
import hashlib
import json
import math
from pathlib import Path
import re
import sys
import unicodedata

ROOT = Path(__file__).resolve().parents[1]
REVISION = '70bb2e84b976b7e960aa89f1c648e09c59f894dd'
TOKEN = re.compile(r'(?<!\w)[+\-−]?\d+(?:[.,]\d+)?(?:st|nd|rd|th)?|\d+(?:[.,]\d+)?(?:st|nd|rd|th)?|[^\W\d_]+(?:[\u2019\'][^\W\d_]+)*|%', re.UNICODE)
NEGATIONS = {'nicht', 'nichts', 'nie', 'niemals', 'weder', 'ohne', 'no', 'not', 'never', 'neither', 'nor', 'without'}
KEIN = {'kein', 'keine', 'keinen', 'keinem', 'keiner', 'keines'}
CONTRACTED = {"can't", "won't", "don't", "doesn't", "didn't", "isn't", "aren't", "wasn't", "weren't", "haven't", "hasn't", "hadn't", "wouldn't", "shouldn't", "couldn't", 'cannot'}
LIMITS = {'original:short': 1.5, 'cleaned:short': 3, 'original:medium': 4, 'cleaned:medium': 4, 'original:long': 5, 'cleaned:long': 5}


def tokens(text):
    return TOKEN.findall(unicodedata.normalize('NFC', text).casefold().replace('’', "'"))


def patterns(aliases):
    result = {}
    for value, variants in aliases.items():
        for variant in [value] + variants:
            key = tuple(tokens(variant))
            if key in result and result[key] != value:
                raise ValueError('Conflicting explicit numeral alias')
            result[key] = value
    return sorted(result.items(), key=lambda item: -len(item[0]))


def number_values(text, aliases):
    words, result, index = tokens(text), [], 0
    while index < len(words):
        match = next(((key, value) for key, value in aliases if tuple(words[index:index + len(key)]) == key), None)
        if match:
            result.append(match[1]); index += len(match[0]); continue
        value = words[index].replace('−', '-').replace(',', '.')
        if re.fullmatch(r'[+\-]?\d+(?:\.\d+)?', value):
            # Decimal structure and negative signs must not disappear into a ratio.
            result.append(str(int(value)) if '.' not in value else value.lstrip('+'))
        index += 1
    return result


def negations(text):
    return ['kein' if word in KEIN else 'not' if word in CONTRACTED else word
            for word in tokens(text) if word in NEGATIONS | KEIN | CONTRACTED]


def term_sequence(text, terms, aliases=None):
    words, result, index = tokens(text), [], 0
    mapping = {}
    for term in terms:
        canonical = ' '.join(tokens(term))
        for variant in [term] + (aliases or {}).get(term, []):
            key = tuple(tokens(variant))
            if not key or key in mapping and mapping[key] != canonical:
                raise ValueError('Conflicting protected-term variant')
            mapping[key] = canonical
    candidates = sorted(mapping.items(), key=lambda item: -len(item[0]))
    while index < len(words):
        match = next(((key, term) for key, term in candidates if tuple(words[index:index + len(key)]) == key), None)
        if match:
            result.append(match[1]); index += len(match[0])
        else:
            index += 1
    return result


def lexical_changes(reference, actual):
    before, after = tokens(reference), tokens(actual)
    return [{'operation': tag, 'reference': ' '.join(before[a:b]), 'actual': ' '.join(after[c:d])}
            for tag, a, b, c, d in difflib.SequenceMatcher(a=before, b=after, autojunk=False).get_opcodes() if tag != 'equal']


def expected_cases(manifest, definitions):
    if (manifest.get('source'), manifest.get('humanAcceptance'), manifest['publicCorpus']['revision']) != ('public-human-fleurs', False, REVISION):
        raise ValueError('Only the pinned explicitly public corpus is accepted')
    if definitions['source']['revision'] != REVISION or definitions['source']['dataset'] != 'google/fleurs' or definitions['source']['license'] != 'cc-by-4.0':
        raise ValueError('Reference definition provenance differs')
    distribution = Counter((case['language'], case['kind']) for case in manifest['cases'])
    if distribution != Counter({(language, kind): count for language in ['de', 'en', 'mixed'] for kind, count in [('short', 4), ('medium', 3), ('long', 3)]}):
        raise ValueError('Expected the full thirty-case balanced plan')
    references = {(row['config'], row['filename']): row for row in definitions['references']}
    if len(references) != len(definitions['references']) or len(references) != 40:
        raise ValueError('Expected forty distinct annotated source references')
    aliases, result = patterns(definitions['numberAliases']), {}
    for case in manifest['cases']:
        if case['id'] in result:
            raise ValueError('Duplicate manifest case')
        if 'sourceIntervals' not in case:
            raise ValueError('Balanced fixture source intervals are required')
        intervals = case['sourceIntervals']
        if case['reference'] != ' '.join(interval['reference'] for interval in intervals):
            raise ValueError('Composite reference differs from full source sentences')
        terms, numbers, cues = [], [], []
        for interval in intervals:
            row = references[(interval['config'], interval['filename'])]
            reference = interval['reference']
            if row['recordID'] != interval['recordID'] or row['referenceSHA256'] != hashlib.sha256(reference.encode()).hexdigest():
                raise ValueError('Source reference changed after annotation')
            if number_values(reference, aliases) != row['numberValues'] or negations(reference) != row['negationCues']:
                raise ValueError('Manual source annotation and extraction differ')
            if any(not term_sequence(reference, [term]) for term in row['protectedTerms']):
                raise ValueError('Annotated protected term absent from source')
            terms += row['protectedTerms']; numbers += row['numberValues']; cues += row['negationCues']
        if number_values(case['reference'], aliases) != numbers or negations(case['reference']) != cues:
            raise ValueError('Composite boundaries changed finite expectations')
        result[case['id']] = {'case': case, 'terms': terms, 'entities': term_sequence(case['reference'], terms, definitions.get('protectedTermAliases')), 'numbers': numbers, 'negations': cues}
    return result, aliases


def audit(manifest, definitions, rows, repeats, partial=False, legacy_quality_only=False):
    expected, aliases = expected_cases(manifest, definitions)
    wanted = {(identity, style, run) for identity in expected for style in ['original', 'cleaned'] for run in range(1, repeats + 1)}
    seen, failures, checked, groups = set(), [], [], defaultdict(list)
    start = next((row for row in rows if row.get('event') == 'suite-start'), None)
    if not start or start.get('source') != 'public-human-fleurs' or start.get('humanAcceptance') is not False or start.get('fixtures') != len(expected) or start.get('repeats') != repeats or start.get('streamedAtRealTime') is not True:
        raise ValueError('Suite start does not match the frozen real-time plan')
    timing_valid = start.get('feedPacing') == 'append-after-capture-deadline' and start.get('feedChunkSamples') == 1600 and start.get('latencyClock') == 'logical-capture-end-including-feed-lag'
    if not timing_valid and not legacy_quality_only:
        raise ValueError('Legacy early-fed audio cannot establish real-time latency; --legacy-quality-only permits content diagnostics only')
    for row in rows:
        if row.get('event') not in ['case', 'case-failure']:
            continue
        key = row['id'], row['style'], row['run']
        if key not in wanted or key in seen:
            raise ValueError('Unexpected or duplicate result tuple')
        seen.add(key)
        if row['event'] == 'case-failure':
            failures.append(row); continue
        spec = expected[row['id']]; case = spec['case']
        if row['reference'] != case['reference'] or row['kind'] != case['kind'] or row['language'] != case['language'] or row['dictionaryEntries'] != 0 or row['contentsLogged'] is not True or row['streamedAtRealTime'] is not True:
            raise ValueError('Result reference, scope or dictionary differs')
        if not math.isfinite(row['audioSeconds']) or abs(row['audioSeconds'] - case['audioSeconds']) > 1 / 16000 or not math.isfinite(row['totalElapsedSeconds']) or row['totalElapsedSeconds'] < row['audioSeconds']:
            raise ValueError('Audio duration or real-time elapsed measurement differs')
        if not math.isfinite(row['stopToResultSeconds']) or row['stopToResultSeconds'] < 0 or not math.isfinite(row['strictOriginalWER']) or row['strictOriginalWER'] < 0 or row['strictReferenceWordCount'] <= 0 or row['strictOriginalWordEdits'] < 0:
            raise ValueError('Invalid timing or WER value')
        if abs(row['strictOriginalWER'] - row['strictOriginalWordEdits'] / row['strictReferenceWordCount']) > 1e-9:
            raise ValueError('WER and edit counts differ')
        if timing_valid and (any(not math.isfinite(row[key]) for key in ['maxEarlyFeedSeconds', 'feedCompletionDelaySeconds', 'modelProcessingAfterFinalFeedSeconds']) or not 0 <= row['maxEarlyFeedSeconds'] <= 1 / 16000 or row['feedCompletionDelaySeconds'] < 0 or row['modelProcessingAfterFinalFeedSeconds'] < 0 or abs(row['stopToResultSeconds'] - row['modelProcessingAfterFinalFeedSeconds'] - row['feedCompletionDelaySeconds']) > .001):
            raise ValueError('Early audio or delivery lag hidden from the logical stop metric')
        details = {}
        for field in ['original', 'text']:
            actual = row[field]
            entities, numbers, cues = term_sequence(actual, spec['terms'], definitions.get('protectedTermAliases')), number_values(actual, aliases), negations(actual)
            details[field] = {'protectedTermsPreserved': entities == spec['entities'], 'numberValuesPreserved': numbers == spec['numbers'], 'negationCuesPreserved': cues == spec['negations'],
                              'expectedTerms': spec['entities'], 'actualTerms': entities, 'expectedNumbers': spec['numbers'], 'actualNumbers': numbers, 'expectedNegations': spec['negations'], 'actualNegations': cues,
                              'lexicalDifferencesForReview': lexical_changes(case['reference'], actual)}
        checked.append({'id': key[0], 'style': key[1], 'run': key[2], 'strictOriginalWER': row['strictOriginalWER'], 'recognitionComplete': row['recognitionComplete'], 'usedFallback': row['usedFallback'],
                        'finiteReferenceChecksPassed': all(d[k] for d in details.values() for k in ['protectedTermsPreserved', 'numberValuesPreserved', 'negationCuesPreserved']), 'details': details,
                        'formatterLexicalChanges': lexical_changes(row['original'], row['text']), 'semanticReviewRequired': True})
        groups[f"{row['style']}:{row['kind']}"].append(row)
    summaries = {}
    for group, values in sorted(groups.items()):
        latency = sorted(row['stopToResultSeconds'] for row in values)
        p95 = latency[math.ceil(len(latency) * .95) - 1]
        summaries[group] = {'runs': len(values), 'processingP95Seconds': p95 if timing_valid else None, 'legacyRecordedP95NotAcceptanceSeconds': None if timing_valid else p95, 'originalInsertionLimitSeconds': LIMITS[group], 'processingWithinLowerBoundLimit': p95 <= LIMITS[group] if timing_valid else None,
                            'incomplete': sum(not r['recognitionComplete'] for r in values), 'fallbacks': sum(r['usedFallback'] for r in values),
                            'weightedStrictOriginalWER': sum(r['strictOriginalWordEdits'] for r in values) / sum(r['strictReferenceWordCount'] for r in values)}
    summary = next((row for row in rows if row.get('event') == 'suite-summary'), None)
    missing = sorted(wanted - seen)
    if not partial and (missing or not summary):
        raise ValueError('Suite incomplete; use --allow-partial only for a pending snapshot')
    if summary and (summary['processedRuns'] != len(checked) or summary['failedRuns'] != len(failures)):
        raise ValueError('Final suite summary differs from actual records')
    finite_failures = sum(not row['finiteReferenceChecksPassed'] for row in checked)
    measured = [row for row in rows if row.get('event') == 'case']
    weighted_wer = sum(row['strictOriginalWordEdits'] for row in measured) / sum(row['strictReferenceWordCount'] for row in measured) if measured else None
    complete = not missing and summary is not None
    failed_metrics = complete and (not timing_valid or weighted_wer > .08 or any(not group['processingWithinLowerBoundLimit'] or group['incomplete'] or group['fallbacks'] for group in summaries.values()))
    status = 'pending' if not complete else 'complete-with-failed-criteria' if finite_failures or failures or failed_metrics else 'complete-awaiting-semantic-and-end-to-end-review'
    return {'status': status, 'suiteComplete': complete, 'expectedRuns': len(wanted), 'observedRuns': len(seen), 'missingRuns': missing, 'runtimeFailures': failures,
            'finiteReferenceFailures': finite_failures, 'weightedStrictOriginalWER': weighted_wer, 'individualRunsAbove8PercentWER': sum(row['strictOriginalWER'] > .08 for row in checked), 'groups': summaries, 'cases': checked,
            'humanAcceptance': False, 'timingProtocolValid': timing_valid, 'semanticAcceptance': 'not established by finite literal checks', 'endToEndInsertionAcceptance': 'not measured; processing latency is only a lower bound' if timing_valid else 'legacy early-fed timing is invalid',
            'limitations': ['Read-speech composites are not spontaneous human dictation.', 'The listed numeral aliases are finite and do not interpret every number word.', 'Negation order does not establish grammatical scope.', 'Unknown added entities/facts and punctuation-induced meaning changes require review.', 'Missing runs, fallbacks and initial outliers remain visible.']}


def self_test():
    aliases = patterns(json.loads((ROOT / 'docs/fixtures/fleurs-reference-checks.json').read_text())['numberAliases'])
    assert number_values('35mm und zwölf sowie 3:2', aliases) == ['35', '12', '3', '2']
    assert number_values('1963', aliases) == number_values('neunzehnhundertdreiundsechzig', aliases) == ['1963']
    assert number_values('a minute', aliases) == number_values('one minute', aliases) == ['1']
    assert number_values('3.2', aliases) != number_values('3:2', aliases)
    assert number_values('-15', aliases) != number_values('15', aliases)
    assert number_values('1964', aliases) != number_values('1963', aliases)
    assert number_values('neunzehnhundertdreiundsechtig', aliases) != ['1963']
    assert negations('Nichtjuden und Juden') == []
    assert negations('kein Entkommen') == ['kein']
    assert negations('not extinct') != negations('extinct')
    assert negations("can't change") == ['not']
    assert term_sequence('HONGKONG und Kowloon.', ['Hongkong', 'Kowloon']) == ['hongkong', 'kowloon']
    assert term_sequence('Hongkong und Köln.', ['Hongkong', 'Kowloon']) != ['hongkong', 'kowloon']
    assert term_sequence('Kowloon und Hongkong', ['Hongkong', 'Kowloon']) != ['hongkong', 'kowloon']
    assert term_sequence('Nichtjuden', ['Juden', 'Nichtjuden']) == ['nichtjuden']
    assert term_sequence('35 millimeters', ['mm'], {'mm': ['millimeters']}) == ['mm']
    assert term_sequence('35 cm', ['mm'], {'mm': ['millimeters']}) != ['mm']
    assert term_sequence('20 %', ['Prozent'], {'Prozent': ['%']}) == ['prozent']
    assert lexical_changes('The patient is ill.', 'The patient is not ill.')
    assert not lexical_changes('Das ist richtig.', 'Das ist richtig!')
    print('20 finite-check regression assertions passed; semantic acceptance remains unproven.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--results', type=Path)
    parser.add_argument('--definitions', type=Path, default=ROOT / 'docs/fixtures/fleurs-reference-checks.json')
    parser.add_argument('--repeats', type=int, default=3)
    parser.add_argument('--allow-partial', action='store_true')
    parser.add_argument('--legacy-quality-only', action='store_true', help='Read preserved early-fed results for content diagnostics; never grade their latency')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        self_test(); return
    if not args.manifest or not args.results or not 1 <= args.repeats <= 10:
        parser.error('--manifest, --results and 1–10 repeats are required')
    if args.output and args.output.resolve() in {p.resolve() for p in [args.manifest, args.results, args.definitions]}:
        raise ValueError('Report output must not overwrite an input')
    manifest_bytes, definition_bytes = args.manifest.read_bytes(), args.definitions.read_bytes()
    manifest, definitions = json.loads(manifest_bytes), json.loads(definition_bytes)
    lines = args.results.read_text().splitlines(keepends=True)
    # A live writer may not yet have finished its final line; never pretend it is a result.
    pending_tail = bool(lines and not lines[-1].endswith('\n'))
    if pending_tail:
        if not args.allow_partial:
            raise ValueError('Unfinished JSONL record')
        lines = lines[:-1]
    rows = [json.loads(line) for line in lines if line.strip()]
    report = audit(manifest, definitions, rows, args.repeats, args.allow_partial, args.legacy_quality_only)
    report.update(manifestSHA256=hashlib.sha256(manifest_bytes).hexdigest(), definitionsSHA256=hashlib.sha256(definition_bytes).hexdigest(), resultsSnapshotSHA256=hashlib.sha256(''.join(lines).encode()).hexdigest(), pendingFinalLine=pending_tail)
    if args.output:
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ['status', 'expectedRuns', 'observedRuns', 'finiteReferenceFailures', 'individualRunsAbove8PercentWER', 'humanAcceptance']}))
    complete = report['suiteComplete']
    failed_complete_metrics = complete and (report['weightedStrictOriginalWER'] > .08 or any(not group['processingWithinLowerBoundLimit'] or group['incomplete'] or group['fallbacks'] for group in report['groups'].values()))
    if report['runtimeFailures'] or report['finiteReferenceFailures'] or failed_complete_metrics:
        sys.exit(1)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Disable FaceFusion NSFW content filter + integrity hash check.

Works on FaceFusion 3.x sources (tested 3.6.1). Idempotent.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


DETECT_NSFW_REPLACEMENT = (
	'def detect_nsfw(vision_frame : VisionFrame) -> bool:\n'
	'\t# facefusion-deck-kit: NSFW filter disabled\n'
	'\treturn False\n'
)

# Match the whole detect_nsfw function body until the next top-level def
DETECT_NSFW_PATTERN = re.compile(
	r'^def detect_nsfw\(vision_frame\s*:\s*VisionFrame\)\s*->\s*bool:\n'
	r'(?:.*\n)*?'
	r'(?=^def )',
	re.MULTILINE,
)

# Hash integrity gate inside common_pre_check (stock FaceFusion)
HASH_BLOCK_PATTERN = re.compile(
	r'^[ \t]*content_analyser_content\s*=\s*inspect\.getsource\(content_analyser\)\.encode\(\)\s*\n'
	r'^[ \t]*content_analyser_hash\s*=\s*hash_helper\.create_hash\(content_analyser_content\)\s*\n'
	r'^[ \t]*\n'
	r'^[ \t]*return all\(module\.pre_check\(\) for module in common_modules\)'
	r'(?:\s+and\s+content_analyser_hash\s*==\s*[\'"][0-9a-fA-F]+[\'"])?\s*\n',
	re.MULTILINE,
)

HASH_BLOCK_REPLACEMENT = (
	'\t# facefusion-deck-kit: content_analyser integrity hash disabled\n'
	'\treturn all(module.pre_check() for module in common_modules)\n'
)

HASH_RETURN_PATTERN = re.compile(
	r'return all\(module\.pre_check\(\) for module in common_modules\)\s+'
	r'and content_analyser_hash\s*==\s*[\'"][0-9a-fA-F]+[\'"]'
)

ALREADY_DISABLED_MARKERS = (
	'facefusion-deck-kit: NSFW filter disabled',
	'facefusion-deck-kit: content_analyser integrity hash disabled',
	'NSFW filter patch',
)


def _common_pre_check_body(text: str) -> str:
	parts = text.split('def common_pre_check', 1)
	if len(parts) < 2:
		return ''
	rest = parts[1]
	# body until next top-level def
	m = re.search(r'\n def |\ndef ', rest[1:] if rest.startswith('()') else rest)
	# simpler: until "\ndef "
	idx = rest.find('\ndef ')
	return rest if idx < 0 else rest[:idx]


def is_detect_nsfw_disabled(text: str) -> bool:
	if 'facefusion-deck-kit: NSFW filter disabled' in text:
		return True
	# short-circuit body already returns False (any prior patch style)
	return bool(
		re.search(
			r'def detect_nsfw\(vision_frame\s*:\s*VisionFrame\)\s*->\s*bool:\s*\n'
			r'(?:[ \t]*#.*\n)*'
			r'[ \t]*return False\s*\n',
			text,
		)
	)


def is_hash_check_disabled(text: str) -> bool:
	if 'facefusion-deck-kit: content_analyser integrity hash disabled' in text:
		return True
	if 'NSFW filter patch' in text and 'content_analyser_hash' in text:
		# commented-out hash lines from manual patch
		body = _common_pre_check_body(text)
		if 'content_analyser_hash ==' not in body and re.search(
			r'return all\(module\.pre_check\(\) for module in common_modules\)',
			body,
		):
			return True
	body = _common_pre_check_body(text)
	if not body:
		return False
	# active (uncommented) hash compare?
	if re.search(r'^\s*content_analyser_hash\s*=', body, re.MULTILINE):
		return False
	if 'content_analyser_hash ==' in body or "content_analyser_hash ==" in body:
		return False
	return bool(
		re.search(
			r'return all\(module\.pre_check\(\) for module in common_modules\)\s*$',
			body,
			re.MULTILINE,
		)
	)


def patch_content_analyser(path: Path, dry_run: bool = False) -> bool:
	text = path.read_text(encoding='utf-8')
	if is_detect_nsfw_disabled(text):
		print(f'[skip] detect_nsfw already disabled: {path}')
		return True

	new_text, n = DETECT_NSFW_PATTERN.subn(DETECT_NSFW_REPLACEMENT + '\n', text, count=1)
	if n == 0:
		print(f'[error] could not find detect_nsfw() in {path}', file=sys.stderr)
		return False

	if not dry_run:
		path.write_text(new_text, encoding='utf-8', newline='\n')
	print(f'[ok] patched detect_nsfw: {path}')
	return True


def patch_core(path: Path, dry_run: bool = False) -> bool:
	text = path.read_text(encoding='utf-8')
	if is_hash_check_disabled(text):
		print(f'[skip] hash check already disabled: {path}')
		return True

	new_text, n = HASH_BLOCK_PATTERN.subn(HASH_BLOCK_REPLACEMENT, text, count=1)
	if n == 0:
		new_text, n = HASH_RETURN_PATTERN.subn(
			'# facefusion-deck-kit: content_analyser integrity hash disabled\n'
			'\treturn all(module.pre_check() for module in common_modules)',
			text,
			count=1,
		)
	if n == 0:
		print(f'[error] could not patch common_pre_check() in {path}', file=sys.stderr)
		return False

	# Comment leftover active hash lines if any remain
	new_text = re.sub(
		r'^([ \t]*)content_analyser_content\s*=\s*inspect\.getsource\(content_analyser\)\.encode\(\)\s*$',
		r'\1# facefusion-deck-kit: content_analyser_content = ...',
		new_text,
		flags=re.MULTILINE,
	)
	new_text = re.sub(
		r'^([ \t]*)content_analyser_hash\s*=\s*hash_helper\.create_hash\(content_analyser_content\)\s*$',
		r'\1# facefusion-deck-kit: content_analyser_hash = ...',
		new_text,
		flags=re.MULTILINE,
	)

	if not dry_run:
		path.write_text(new_text, encoding='utf-8', newline='\n')
	print(f'[ok] patched common_pre_check: {path}')
	return True


def clear_pycache(facefusion_pkg: Path) -> None:
	cache = facefusion_pkg / '__pycache__'
	if not cache.is_dir():
		return
	for name in ('content_analyser', 'core'):
		for pyc in cache.glob(f'{name}*.pyc'):
			try:
				pyc.unlink()
				print(f'[ok] removed {pyc.name}')
			except OSError as exc:
				print(f'[warn] could not remove {pyc}: {exc}')


def resolve_package_dir(root: Path) -> Path | None:
	"""Accept Pinokio root, facefusion clone root, or package dir."""
	candidates = [
		root / 'facefusion' / 'facefusion',
		root / 'facefusion',
		root,
	]
	for cand in candidates:
		if (cand / 'content_analyser.py').is_file() and (cand / 'core.py').is_file():
			return cand
	return None


def main() -> int:
	parser = argparse.ArgumentParser(description='Disable FaceFusion NSFW filter')
	parser.add_argument(
		'target',
		type=Path,
		help='Pinokio app folder, FaceFusion clone, or facefusion package folder',
	)
	parser.add_argument('--dry-run', action='store_true')
	args = parser.parse_args()

	root = args.target.resolve()
	pkg = resolve_package_dir(root)
	if pkg is None:
		print(f'[error] content_analyser.py / core.py not found under {root}', file=sys.stderr)
		return 1

	ok = True
	ok &= patch_content_analyser(pkg / 'content_analyser.py', dry_run=args.dry_run)
	ok &= patch_core(pkg / 'core.py', dry_run=args.dry_run)
	if ok and not args.dry_run:
		clear_pycache(pkg)
	return 0 if ok else 1


if __name__ == '__main__':
	sys.exit(main())

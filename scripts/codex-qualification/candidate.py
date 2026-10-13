"""Offline full-production build-context assembly. Never executes a builder.

Only committed Git blobs are exported. A proposed build argv is data, not an
execution entrypoint or approval. Builder, network/dependency, image, filesystem
and authentication evidence remain pending; importing this module writes nothing.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path, PurePosixPath
import posixpath
import stat
from prepare import (INPUT_ROOTS, Refused, canonical, controlled_dockerfile, git,
                     preparation, require, sha, synthetic_browser_config)


COMPONENT_ROOT = 'scripts/codex-qualification'
COMPONENT_PATHS = (COMPONENT_ROOT, 'scripts/lib/codex-qualification.test.sh')


def checked_destination(repo, directory):
    directory = Path(directory)
    repo = Path(repo).resolve()
    require(directory.is_absolute() and '..' not in directory.parts,
            'Absolute task directory without traversal required')
    require(not any(part in ('.git', '.ssh', '.aws', '.codex', '.agents') for part in directory.parts),
            'Account/credential/control directories are outside candidate scratch')
    require(directory == directory.resolve(strict=False), 'Symlink destination or ancestor refused')
    project_root = repo / '.soleur'
    if directory.is_relative_to(project_root):
        allowed_root = project_root
    else:
        require(not directory.is_relative_to(repo), 'Candidate cannot write into the source tree')
        allowed_root = Path('/tmp')
        require(directory.is_relative_to(allowed_root), 'Only /tmp or this worktree .soleur task scratch admitted')
    require(directory != allowed_root and directory.parent.is_dir(), 'Fresh task leaf with existing parent required')
    require(not directory.exists() and not directory.is_symlink(), 'Existing candidate destination refused')
    return directory, allowed_root


def current_source(repo, source):
    require(git(repo, 'rev-parse', 'HEAD').decode().strip() == source, 'Source is no longer HEAD')
    require(not git(repo, 'status', '--porcelain', '--untracked-files=no', '--',
                    *INPUT_ROOTS, *COMPONENT_PATHS).strip(), 'Runtime/preparation source changed')


def safe_relative(value):
    require(isinstance(value, str) and '\x00' not in value, 'Regular source path required')
    path = PurePosixPath(value)
    require(not path.is_absolute() and value == str(path) and
            all(part not in ('', '.', '..') for part in path.parts), 'Source path traversal/ambiguity refused')
    return path


def candidate_spec(repo, source, directory):
    """Read current committed full-production inputs and return an offline recipe."""
    directory, _root = checked_destination(repo, directory)
    current_source(repo, source)
    contract = preparation(repo, source)
    components = {row['path']: row for row in contract['component_manifest']}
    # Bind the code actually performing preparation, not merely some older copy
    # of the same path in HEAD. Isolated Git fixtures commit these exact bytes.
    for name in ('candidate.py', 'prepare.py'):
        relative = COMPONENT_ROOT + '/' + name
        require(relative in components and components[relative]['sha256'] ==
                sha((Path(__file__).parent / name).read_bytes()), 'Executing preparation component is not committed current source')
    identity = contract['identity']
    require(identity['runtime_input_sha256'] == sha(canonical(contract['manifest'])) and
            identity['schema_sha256'] == sha(canonical(contract['forward_migrations'])) and
            identity['browser_contract_sha256'] == sha(canonical(contract['browser'])) and
            identity['preparation_components_sha256'] == sha(canonical(contract['component_manifest'])) and
            contract['pairing_sha256'] == sha(canonical(identity)), 'Preparation identity differs from its complete inventories')
    exports = []
    paths = {row['path']: row for row in contract['manifest']}
    for row in contract['manifest']:
        path = safe_relative(row['path'])
        require(any(str(path).startswith(root + '/') for root in INPUT_ROOTS), 'Input lies outside full production source roots')
        require(str(path) != 'apps/web-platform/_plugin-vendored' and
                not str(path).startswith('apps/web-platform/_plugin-vendored/'), 'Tracked vendor subtree collides with exact source vendoring')
        names = ['runtime/' + row['path']]
        if row['path'].startswith('plugins/soleur/'):
            names.append('runtime/apps/web-platform/_plugin-vendored/' + row['path'].removeprefix('plugins/soleur/'))
        for name in names:
            exports.append({'path': name, 'source_path': row['path'], 'blob': row['blob'],
                            'mode': row['mode'], 'sha256': row['sha256'], 'bytes': row['bytes']})
    require('apps/web-platform/Dockerfile' in paths and paths['apps/web-platform/Dockerfile']['mode'] in ('100644', '100755'),
            'Production Dockerfile must be a committed regular blob')
    original = git(repo, 'cat-file', 'blob', paths['apps/web-platform/Dockerfile']['blob'])
    controlled = controlled_dockerfile(original.decode()).encode()
    require(identity['production_dockerfile_sha256'] == sha(original) and
            identity['controlled_dockerfile_sha256'] == sha(controlled), 'Production/compiler Dockerfile identity changed')
    for name, data in [('production.Dockerfile', original), ('controlled.Dockerfile', controlled)]:
        exports.append({'path': name, 'source_path': 'apps/web-platform/Dockerfile',
                        'mode': '100644', 'sha256': sha(data), 'bytes': len(data)})
    require(len({row['path'] for row in exports}) == len(exports), 'Export destination collision refused')
    config = synthetic_browser_config()
    require(config['url'] == contract['browser']['url'] and sha(config['anon_key'].encode()) ==
            contract['browser']['anon_key_sha256'], 'Public synthetic build auth differs from browser contract')
    require(config['claims']['exp'] > int(datetime.now(timezone.utc).timestamp()),
            'Synthetic browser contract expired; fresh reviewed preparation required')
    build_args = {'NEXT_PUBLIC_SUPABASE_URL': config['url'], 'NEXT_PUBLIC_SUPABASE_ANON_KEY': config['anon_key'],
                  'BUILD_SHA': source, 'BUILD_VERSION': 'codex9051-local-' + source[:12]}
    context = directory / 'runtime/apps/web-platform'
    argv = ['/usr/bin/docker', '--config', str(directory / 'docker-config'), 'build', '--pull=false',
            '--progress=plain', '--file', str(directory / 'controlled.Dockerfile'),
            '--iidfile', str(directory / 'built-image-id.txt'), '--tag', 'codex9051-local-candidate:' + source]
    for name, value in sorted(build_args.items()):
        argv += ['--build-arg', name + '=' + value]
    argv.append(str(context))
    recipe = {'status': 'proposed-unreviewed-operational-builder-recipe', 'execute_authorized': False,
              'argv': argv, 'working_directory': str(directory),
              'replace_environment': True, 'environment': {'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8',
                  'HOME': str(directory / 'builder-home'), 'DOCKER_CONFIG': str(directory / 'docker-config')},
              'build_args': build_args, 'credential_forwarding': False,
              'builder_binary_sha256': None, 'builder_daemon_and_namespace_review': 'pending',
              'dependency_download_and_network_review': 'pending-production-install-layers',
              'compiler_network': 'four-original-production-compiler-directives-only-network-none',
              'required_before_execution': ['reviewed-exact-builder-binary-daemon-and-operation-admission',
                                            'reviewed-source-bound-build-context-and-dependency-network-boundaries',
                                            'fresh-exact-build-and-rehearsal-approval'],
              'required_after_build': ['immutable-built-image-ID-and-filesystem-receipts',
                                       'owned-local-synthetic-browser-auth-evidence']}
    exports.sort(key=lambda row: row['path'])
    return {'status': 'offline-build-context-preparation-only', 'identity': identity,
            'pairing_sha256': contract['pairing_sha256'], 'browser': contract['browser'],
            'destination': str(directory), 'runtime_input_count': len(contract['manifest']),
            'forward_migration_count': len(contract['forward_migrations']),
            'component_count': len(contract['component_manifest']),
            'vendor_input_count': sum(row['path'].startswith('plugins/soleur/') for row in contract['manifest']),
            'export_file_count': len(exports), 'export_manifest': exports,
            'export_manifest_sha256': sha(canonical(exports)), 'build_recipe': recipe,
            'build_recipe_sha256': sha(canonical(recipe)), 'image_id': None, 'execute_authorized': False,
            'operations': {'docker': 0, 'build': 0, 'startup': 0, 'sql': 0, 'provider': 0, 'credentials_read': 0}}


def open_directory(task_fd, parts, create=False):
    """Walk only descriptor-relative directories, never following source links."""
    descriptor = os.dup(task_fd)
    try:
        for part in parts:
            require(part not in ('', '.', '..') and '/' not in part, 'Unsafe export directory component')
            if create:
                try:
                    os.mkdir(part, mode=0o700, dir_fd=descriptor)
                except FileExistsError:
                    pass
            next_descriptor = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = next_descriptor
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


def write_blob(task_fd, relative, content, mode):
    """Create one new regular file or safe source link under the pinned task fd."""
    path = safe_relative(relative)
    parent = open_directory(task_fd, path.parts[:-1], create=True)
    try:
        if mode == '120000':
            target = content.decode()
            require(not target.startswith('/') and '\x00' not in target, 'Unsafe exported symlink')
            os.symlink(target, path.name, dir_fd=parent)
        else:
            require(mode in ('100644', '100755'), 'Unsupported file mode')
            descriptor = os.open(path.name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                 0o600, dir_fd=parent)
            with os.fdopen(descriptor, 'wb') as stream:
                stream.write(content)
                os.fchmod(stream.fileno(), 0o755 if mode == '100755' else 0o644)
    finally:
        os.close(parent)


def leaf_inventory(task_fd):
    result = set()
    def visit(descriptor, prefix):
        for name in os.listdir(descriptor):
            info = os.stat(name, dir_fd=descriptor, follow_symlinks=False)
            path = prefix + name
            if stat.S_ISDIR(info.st_mode):
                child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=descriptor)
                try:
                    visit(child, path + '/')
                finally:
                    os.close(child)
            else:
                result.add(path)
    visit(task_fd, '')
    return result


def verify_exports(task_fd, rows):
    require(leaf_inventory(task_fd) == {row['path'] for row in rows}, 'Export file inventory differs from complete source mapping')
    for row in rows:
        path = safe_relative(row['path'])
        parent = open_directory(task_fd, path.parts[:-1])
        try:
            info = os.stat(path.name, dir_fd=parent, follow_symlinks=False)
            if row['mode'] == '120000':
                require(stat.S_ISLNK(info.st_mode), 'Exported source link became a different file type')
                content = os.readlink(path.name, dir_fd=parent).encode()
            else:
                require(stat.S_ISREG(info.st_mode) and stat.S_IMODE(info.st_mode) ==
                        (0o755 if row['mode'] == '100755' else 0o644), 'Exported source file type/mode differs')
                descriptor = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=parent)
                with os.fdopen(descriptor, 'rb') as stream:
                    content = stream.read()
            require(len(content) == row['bytes'] and sha(content) == row['sha256'], 'Exported bytes differ from committed source')
        finally:
            os.close(parent)


def metadata(spec):
    """Content-free preview/receipt; public fixture JWT lives only in recipe data."""
    return {key: value for key, value in spec.items() if key not in ('build_recipe', 'export_manifest')}


def assemble(repo, source, directory):
    spec = candidate_spec(repo, source, directory)
    directory, allowed_root = checked_destination(repo, directory)
    root_fd = os.open(allowed_root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    parent_fd = None
    task_fd = None
    try:
        relative = directory.relative_to(allowed_root)
        parent_fd = open_directory(root_fd, relative.parts[:-1])
        # Exclusive creation is the only write outside the new task subtree.
        os.mkdir(relative.name, mode=0o700, dir_fd=parent_fd)
        task_fd = os.open(relative.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)
        paths = {row['path'] for row in spec['export_manifest']}
        # Write links last. No subsequent regular-file write can traverse a link.
        for row in sorted(spec['export_manifest'], key=lambda item: item['mode'] == '120000'):
            if 'blob' in row:
                content = git(repo, 'cat-file', 'blob', row['blob'])
            else:
                content = git(repo, 'show', source + ':apps/web-platform/Dockerfile')
                if row['path'] == 'controlled.Dockerfile':
                    content = controlled_dockerfile(content.decode()).encode()
            require(sha(content) == row['sha256'] and len(content) == row['bytes'], 'Source blob bytes differ from contract')
            if row['mode'] == '120000':
                target = posixpath.normpath(posixpath.join(posixpath.dirname(row['path']), content.decode()))
                module = ('runtime/apps/web-platform/_plugin-vendored/' if row['path'].startswith('runtime/apps/web-platform/_plugin-vendored/')
                          else next('runtime/' + root + '/' for root in INPUT_ROOTS if row['path'].startswith('runtime/' + root + '/')))
                require(target.startswith(module) and target in paths, 'Exported symlink leaves its exact module source mapping')
            write_blob(task_fd, row['path'], content, row['mode'])
        verify_exports(task_fd, spec['export_manifest'])
        current_source(repo, source)
        for relative in ('builder-home', 'docker-config'):
            descriptor = open_directory(task_fd, (relative,), create=True)
            os.close(descriptor)
        # Configuration is generated empty, never copied from the operator HOME.
        write_blob(task_fd, 'docker-config/config.json', b'{}\n', '100644')
        config_fd = open_directory(task_fd, ('docker-config',))
        try:
            os.chmod('config.json', 0o600, dir_fd=config_fd, follow_symlinks=False)
        finally:
            os.close(config_fd)
        write_blob(task_fd, 'build-recipe.json', canonical(spec['build_recipe']) + b'\n', '100644')
        receipt = {**metadata(spec), 'export_manifest': spec['export_manifest']}
        write_blob(task_fd, 'candidate-contract.json', canonical(receipt) + b'\n', '100644')
        return metadata(spec)
    finally:
        if task_fd is not None:
            os.close(task_fd)
        if parent_fd is not None:
            os.close(parent_fd)
        os.close(root_fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--source-sha', required=True)
    parser.add_argument('--directory', type=Path, required=True)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument('--preview', action='store_true')
    action.add_argument('--assemble', action='store_true')
    args = parser.parse_args()
    result = assemble(args.repo, args.source_sha, args.directory) if args.assemble else metadata(
        candidate_spec(args.repo, args.source_sha, args.directory))
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()

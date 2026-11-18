"""Synthetic profiles for offline fixtures only; no production role attestation."""
import copy

def fixture_profiles(project, images, bind=False):
    image = next(iter(images.values()))
    config = {'Entrypoint': ['fixture-entry'], 'Cmd': ['fixture-server'],
              'Env': [], 'User': '1001', 'WorkingDir': '/app'}
    profiles = {}
    for role in ('db', 'kong', 'auth', 'inbucket', 'rest', 'storage'):
        profiles['supabase_' + role + '_' + project] = {
            'role': role, 'image': image, 'image_config': copy.deepcopy(config),
            'create': copy.deepcopy(config), 'host': {}, 'aliases': [],
            'exec': [{'Cmd': command, 'Env': env, 'User': '', 'WorkingDir': ''}
                     for command in (['node', '--version'], ['fixture'])
                     for env in ([], ['HOME=/tmp', 'PATH=/usr/bin:/bin'])]}
    if bind:
        profiles['supabase_db_' + project]['host']['Binds'] = [
            'supabase_db_' + project + ':/var/lib/postgresql/data']
    for index in range(1, 9):
        profile = copy.deepcopy(profiles['supabase_db_' + project])
        profile['role'] = 'migration'
        profiles['codex9051-job-' + project + '-' + str(index)] = profile
    return profiles

def fixture_image(image):
    return {'Id': image, 'Config': fixture_profiles('fixture', {image: image})[
            'supabase_db_fixture']['image_config']}

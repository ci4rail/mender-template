import os
import subprocess
import click
import yaml
from dotenv import load_dotenv

load_dotenv()

CONFIG_FILE = "config.yaml"

# Helper function to load the YAML configuration file
def load_config():
    if not os.path.exists(CONFIG_FILE):
        return {"project": "", "application": []}
    with open(CONFIG_FILE, 'r') as f:
        return yaml.safe_load(f)

# Function to run shell commands
def run_command(command, capture_output=False, verbose=False):
    """Run shell commands and print them if verbose is enabled."""
    if verbose:
        click.echo(f"Executing: {command}")
    try:
        result = subprocess.run(command, shell=True, check=True, text=True, capture_output=capture_output)
        return result.stdout.strip() if capture_output else None
    except subprocess.CalledProcessError as e:
        click.echo(f"Error: {str(e)}")
        exit(1)

# Helper function to construct environment variables for images
def construct_env_variables(images):
    env_vars = []
    for image in images:
        name = image.get('name', '')
        image_path = image.get('image', '')
        if name and image_path:
            env_vars.append(f"{name}={image_path}")
    return env_vars

# Helper function to format images for the build command
def format_images_for_build(images):
    return ' '.join([f"--image \"{image['image']}\"" for image in images if 'image' in image])

# Build Docker image
def build_docker_image(docker_image_name, verbose):
    """Builds the Docker image using the Dockerfile at the specified path."""
    click.echo(f"Building Docker image {docker_image_name} from Dockerfile...")
    build_command = f"docker build -t {docker_image_name} -f Dockerfile ."
    run_command(build_command, verbose=verbose)
    click.echo(f"Docker image {docker_image_name} built successfully.")

# Build artifacts for each platform, device, and manifest
@click.command()
@click.option('--version', default=lambda: run_command('git rev-parse --short HEAD', capture_output=True), help='Version or Git hash for the build. Default is the current Git hash.')
@click.option('--output-dir', default='./artifacts', help='Output directory for the generated artifacts.')
@click.option('--verbose', is_flag=True, help='Enable detailed output of executed commands.')
@click.option('--use-local', is_flag=True, help='Use local images for the build.')
def build_artifacts(version, output_dir, verbose, use_local):
    """Build Mender artifacts for each platform, device type, and manifest."""
    config = load_config()
    project_name = config.get('project', 'project')
    docker_image_name = f"{project_name}-build" 

    # Get UID, GID, and DID values from the host system
    uid = run_command("id -u", capture_output=True)
    gid = run_command("id -g", capture_output=True)
    did = run_command("getent group docker | cut -d: -f3", capture_output=True)

    # Build Docker image before building artifacts
    build_docker_image(docker_image_name, verbose)

    applications = config.get('application', [])
    os.makedirs(output_dir, exist_ok=True)

    for app in applications:
        app_name = app.get('name', '')
        platforms = app.get('architectures', [])
        device_types = app.get('device-types', [])
        manifest = app.get('manifest', '')
        images = app.get('images', [])

        # Construct environment variables based on images
        env_vars = construct_env_variables(images)
        env_vars_str = ' '.join([f"-e {env}" for env in env_vars])

        # Format images for the build command
        images_str = format_images_for_build(images)

        for platform in platforms:
            formatted_platform = platform.replace('/', '_')
            
            for device in device_types:
                artifact_name = f"{project_name}-{app_name}-{device}-{formatted_platform}-{version}"
                output_path = f"{output_dir}/{artifact_name}.mender"

                click.echo(f"Building Mender artifact for {app_name}, device {device}, platform {platform} with commit {version}...")

                # Docker run command with mounted Docker socket and UID/GID/DID environment variables
                build_command = (
                    f"docker run --rm "
                    f"-v {os.getcwd()}:/workdir "
                    f"-v /var/run/docker.sock:/var/run/docker.sock "
                    f"-v /run/containerd/containerd.sock:/run/containerd/containerd.sock "
                    f"-e UID={uid} "
                    f"-e GID={gid} "
                    f"-e DID={did} "
                    f"{env_vars_str} "
                    f"{docker_image_name} "
                    f"app-gen --artifact-name \"{artifact_name}\" "
                    f"--use-local-images " if use_local else ""  # Use local images if flag is enabled
                    f"--device-type \"{device}\" "
                    f"--platform \"{platform}\" "
                    f"--application-name \"{app_name}\" "
                    f"{images_str} "  # Pass the images for the app
                    f"--orchestrator \"docker-compose\" "
                    f"--manifests-dir \"/workdir/{manifest}\" "
                    f"--output-path \"/workdir/{output_path}\" "
                    f"-- "
                    f"--software-name=\"{app_name}\" "
                    f"--software-version=\"{version}\""
                )
                
                run_command(build_command, verbose=verbose)
                click.echo(f"Mender artifact built successfully: {output_path}")

# Upload Mender artifacts
@click.command()
@click.option('--output-dir', default='./artifacts', help='Output directory containing the artifacts to upload.')
@click.option('--verbose', is_flag=True, help='Enable detailed output of executed commands.')
def upload_artifacts(output_dir, verbose):
    """Upload Mender artifacts to the Mender server."""
    config = load_config()
    project_name = config.get('project', 'project')
    docker_image_name = f"{project_name}-build"

    mender_server_url = os.getenv("MENDER_SERVER_URL")
    mender_username = os.getenv("MENDER_USERNAME")
    mender_password = os.getenv("MENDER_PASSWORD")
    mender_tenant_token = os.getenv("MENDER_TENANT_TOKEN")

    # Get UID, GID, and DID values from the host system
    uid = run_command("id -u", capture_output=True)
    gid = run_command("id -g", capture_output=True)
    did = run_command("getent group docker | cut -d: -f3", capture_output=True)

    # Login to Mender CLI
    login_command = (
        f"docker run --rm -v {os.getcwd()}:/workdir -v cache:/home/user/.cache/mender/ {docker_image_name} "
        f"mender-cli login --server {mender_server_url} --username {mender_username} "
        f"--password {mender_password} --token-value {mender_tenant_token}"
    )
    run_command(login_command, verbose=verbose)

    # Upload all Mender artifacts
    for artifact in os.listdir(output_dir):
        if artifact.endswith(".mender"):
            artifact_path = os.path.join(output_dir, artifact)
            click.echo(f"Uploading {artifact_path} to Mender server...")
            upload_command = (
                f"docker run --rm -v {os.getcwd()}:/workdir -v cache:/home/user/.cache/mender/ {docker_image_name} "
                f"mender-cli artifacts upload {artifact_path} --server {mender_server_url}"
            )
            run_command(upload_command, verbose=verbose)
            click.echo(f"Uploaded {artifact_path} successfully")

@click.group()
def cli():
    pass

cli.add_command(build_artifacts)
cli.add_command(upload_artifacts)

if __name__ == '__main__':
    cli()

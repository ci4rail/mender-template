# os.putenv('DOCKER_HOST', 'tcp://localhost:2375')

# Get image name and tag from environment variables or set default values
# nats_address = os.getenv('NATS_ADDRESS', 'localhost')
# nats_port = os.getenv('NATS_PORT', '4222')
# nats_token = os.getenv('NATS_TOKEN', 'your-secure-token' )

# os.putenv('NATS_ADDRESS', nats_address)
# os.putenv('NATS_PORT', nats_port)
# os.putenv('NATS_TOKEN', nats_token)

docker_compose([
    'app/benthos-http-producer/manifest/docker-compose.yaml',
    'app/app1/

])

include('app/go-template/image.tilt')

# include('app/go-template/Tiltfile')
# include('app/nats/Tiltfile')


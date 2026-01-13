docker build -t my-turnserver -f Dockerfile.turnserver .
docker build -t my-turnclient -f Dockerfile.turnclient .

docker network create --subnet 10.244.0.0/24 turnnet

docker run -d --name turnserver --network turnnet --ip 10.244.0.24 \
  -e LISTEN_IP=10.244.0.24 \
  -e RELAY_IP=10.244.0.24 \
  -e REALM=myrealm \
  -e TURN_USER=demo -e TURN_PASS=demo \
  -p 3478:3478/udp -p 3478:3478/tcp \
  -p 49160-49200:49160-49200/udp \
  my-turnserver

docker run --rm --network turnnet --ip 10.244.0.25 \
  -e SERVER_HOST=10.244.0.24 \
  -e LOCAL_IP=10.244.0.25 \
  -e REALM=myrealm -e TURN_USER=demo -e TURN_PASS=demo \
  -e PACKETS=10 \
  my-turnclient


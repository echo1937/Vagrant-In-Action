docker run -d \
    -p 9090:9090 \
    -v /vagrant/prometheus.yml:/etc/prometheus/prometheus.yml \
    prom/prometheus
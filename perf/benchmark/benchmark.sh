#!/bin/bash
  
# Exit immediately for non zero status
set -e
# Check unset variables
set -u
# Print commands
set -x

export LC_ALL=C.UTF-8
export LANG=C.UTF-8

SVC_BASELINE_URL=http://fortio-server-raw-perf.apps.ocp1.example.com
SVC_SIDECAR_URL=http://fortio-server.istio-system.apps.ocp1.example.com
ECHO_RESP_SIZE=1024
PAYLOAD_SIZE=512
SVC_PATH="echo?size=${ECHO_RESP_SIZE}"
TEST_DURATION=180s
EXPECTED_QPS=10000
JITTER=true
HTTP_BUFFER_KB=1024

BASE_LABEL="${TEST_DURATION}-${EXPECTED_QPS}qps-jitter-${JITTER}-size${ECHO_RESP_SIZE}"

# housekeeping
rm -fv *.json

for i in 2 4 8 16 32 64;
do
  # baseline
  echo -e '\n'
  LABELS="c${i}-${BASE_LABEL}-no-sidecar"
  TEST_URL="${SVC_BASELINE_URL}/${SVC_PATH}"
  fortio load -c ${i} -qps ${EXPECTED_QPS} -t ${TEST_DURATION} -a -jitter=${JITTER} -quiet -p "50,75,90,99,99.9" -r 0.001 -httpbufferkb ${HTTP_BUFFER_KB} -labels ${LABELS} -payload-size ${PAYLOAD_SIZE} ${TEST_URL}
  sleep 10
  echo -e '\n'
  
  # sidecar
  LABELS="c${i}-${BASE_LABEL}-envoy-sidecar"
  TEST_URL="${SVC_SIDECAR_URL}/${SVC_PATH}"
  fortio load -c ${i} -qps ${EXPECTED_QPS} -t ${TEST_DURATION} -a -jitter=${JITTER} -quiet -p "50,75,90,99,99.9" -r 0.001 -httpbufferkb ${HTTP_BUFFER_KB}  -labels ${LABELS} -payload-size ${PAYLOAD_SIZE} ${TEST_URL}
  sleep 30
  echo -e '\n'

done;


# collect metrics
JSON_PATH=.
TEMP_PATH="${TMPDIR:-/tmp}"
FORTIO_JSON_DATA_PATH="${TEMP_PATH}/fortio_json_data"
mkdir -p "${FORTIO_JSON_DATA_PATH}"
rm -fv "${FORTIO_JSON_DATA_PATH}"/*.json
cp -fv "${JSON_PATH}"/*.json "${FORTIO_JSON_DATA_PATH}"

STAMP=$(date '+%Y%m%d%H%M%S')_$(echo $RANDOM)
export CSV_OUTPUT="$(mktemp /tmp/benchmark_${STAMP}.csv)"
export PROMETHEUS_URL=https://prometheus-k8s-openshift-monitoring.apps.ocp1.example.com
export PROMETHEUS_TOKEN=$(oc whoami -t)

pipenv run python3 runner/fortio.py --json_path="${JSON_PATH}" --prometheus=${PROMETHEUS_URL} --prometheus_token=${PROMETHEUS_TOKEN} --csv_output="$CSV_OUTPUT" --csv StartTime,ActualDuration,Labels,NumThreads,ActualQPS,p50,p75,p90,p99,p999,cpu_mili_avg_istio_proxy_fortio_server,mem_milli_avg_istio_proxy_fortio_server

pipenv run python3 runner/graph.py --graph_type=latency-p50 --x_axis=conn --telemetry_modes=no-sidecar,envoy-sidecar --query_str=ActualQPS=="${EXPECTED_QPS}" --query_list=2,4,8,16,32,64 --csv_filepath="$CSV_OUTPUT" --graph_title="latency-p50-jitter-${JITTER}.png"
pipenv run python3 runner/graph.py --graph_type=latency-p90 --x_axis=conn --telemetry_modes=no-sidecar,envoy-sidecar --query_str=ActualQPS=="${EXPECTED_QPS}" --query_list=2,4,8,16,32,64 --csv_filepath="$CSV_OUTPUT" --graph_title="latency-p90-jitter-${JITTER}.png"
pipenv run python3 runner/graph.py --graph_type=latency-p99 --x_axis=conn --telemetry_modes=no-sidecar,envoy-sidecar --query_str=ActualQPS=="${EXPECTED_QPS}" --query_list=2,4,8,16,32,64 --csv_filepath="$CSV_OUTPUT" --graph_title="latency-p99-jitter-${JITTER}.png"

pipenv run python3 runner/graph.py --graph_type=cpu-server --x_axis=conn --telemetry_modes=no-sidecar,envoy-sidecar --query_str=ActualQPS=="${EXPECTED_QPS}" --query_list=2,4,8,16,32,64 --csv_filepath="$CSV_OUTPUT" --graph_title="cpu-server-jitter-${JITTER}.png"
pipenv run python3 runner/graph.py --graph_type=mem-server --x_axis=conn --telemetry_modes=no-sidecar,envoy-sidecar --query_str=ActualQPS=="${EXPECTED_QPS}" --query_list=2,4,8,16,32,64 --csv_filepath="$CSV_OUTPUT" --graph_title="mem-server-jitter-${JITTER}.png"

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';
import {
  cnpjForIteration,
  expectCapacityRejection,
  fixture,
  fixtureMode,
  loadScenario,
  targetUrl,
} from './common.js';

const expectedCapacity503 = new Counter('radar_expected_capacity_503');
const unexpectedStatuses = new Counter('radar_unexpected_status');
const retryAfterMissing = new Counter('radar_retry_after_missing');

export const options = {
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)'],
  scenarios: {
    radar_cnpj: loadScenario('radar_cnpj'),
  },
  thresholds: {
    http_req_failed: __ENV.K6_EXPECT_CAPACITY_REJECTION === 'true'
      ? ['rate<1']
      : ['rate<0.05'],
    http_req_duration: ['p(95)<5000', 'p(99)<10000'],
    checks: ['rate>0.95'],
  },
};

export default function () {
  const useCep = fixtureMode() !== 'all-miss' && __ITER % 2 === 1;
  const endpoint = useCep ? 'radar_cep' : 'radar_estabelecimento';
  const path = useCep
    ? `/internal/v1/ceps/${fixture('K6_CEP')}`
    : `/internal/v1/empresas/${cnpjForIteration()}/estabelecimento`;
  const response = http.get(`${targetUrl()}${path}`, {
    headers: { Accept: 'application/json' },
    tags: { endpoint },
  });
  const expected503 = expectCapacityRejection() && response.status === 503;
  if (expected503) {
    expectedCapacity503.add(1);
    if (!response.headers['Retry-After']) {
      retryAfterMissing.add(1);
    }
  } else if (response.status !== 200) {
    unexpectedStatuses.add(1);
  }
  check(response, {
    'Radar returns data or expected capacity rejection': (res) =>
      res.status === 200 || (
        expectCapacityRejection()
        && res.status === 503
        && Boolean(res.headers['Retry-After'])
      ),
  });
  if (__ENV.K6_EXECUTOR === 'constant-vus') {
    sleep(1);
  }
}

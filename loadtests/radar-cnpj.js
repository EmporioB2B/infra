import http from 'k6/http';
import { check } from 'k6';
import { fixture, planStages, targetUrl } from './common.js';

export const options = {
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)'],
  scenarios: {
    radar_cnpj: {
      executor: 'ramping-arrival-rate',
      startRate: 0,
      timeUnit: '1s',
      preAllocatedVUs: 10,
      maxVUs: 50,
      stages: planStages(),
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<5000', 'p(99)<10000'],
    checks: ['rate>0.95'],
  },
};

export default function () {
  const useCep = __ITER % 2 === 1;
  const endpoint = useCep ? 'radar_cep' : 'radar_estabelecimento';
  const path = useCep
    ? `/internal/v1/ceps/${fixture('K6_CEP')}`
    : `/internal/v1/empresas/${fixture('K6_CNPJ')}/estabelecimento`;
  const response = http.get(`${targetUrl()}${path}`, {
    headers: { Accept: 'application/json' },
    tags: { endpoint },
  });
  check(response, {
    'Radar returns data': (res) => res.status === 200,
  });
}

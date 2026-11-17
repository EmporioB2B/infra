import http from 'k6/http';
import { check } from 'k6';
import { bearerOptions, fixture, login, planStages } from './common.js';

export const options = {
  scenarios: {
    api_radar: {
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

export function setup() {
  return { accessToken: login() };
}

export default function (data) {
  const response = http.post(
    `${__ENV.K6_BASE_URL.replace(/\/+$/, '')}/api/v1/administracao/organizacoes/consultar-cnpj`,
    JSON.stringify({ cnpj: fixture('K6_CNPJ') }),
    bearerOptions(data.accessToken, 'administracao_consultar_cnpj'),
  );
  check(response, {
    'API→Radar returns data': (res) => res.status === 200,
  });
}

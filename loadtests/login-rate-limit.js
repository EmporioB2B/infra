import http from 'k6/http';
import { check } from 'k6';
import { Counter } from 'k6/metrics';
import { env, headers, targetUrl } from './common.js';

const rateLimitResponses = new Counter('login_rate_limit_429');

export const options = {
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)'],
  scenarios: {
    login_rate_limit: {
      executor: 'per-vu-iterations',
      vus: 1,
      iterations: 7,
      maxDuration: '2m',
    },
  },
  thresholds: {
    checks: ['rate>0.85'],
    login_rate_limit_429: ['count>0'],
  },
};

export default function () {
  const response = http.post(
    `${targetUrl()}/api/v1/auth/login`,
    JSON.stringify({
      email: env('K6_LOGIN_EMAIL'),
      senha: `${env('K6_LOGIN_PASSWORD')}-invalid`,
    }),
    { headers: headers(), tags: { endpoint: 'auth_login_rate_limit' } },
  );
  check(response, {
    'invalid login is not successful': (res) => [401, 429].includes(res.status),
    '429 has Retry-After': (res) => res.status !== 429 || Boolean(res.headers['Retry-After']),
  });
  if (response.status === 429) {
    rateLimitResponses.add(1);
  }
}

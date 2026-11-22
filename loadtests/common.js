import http from 'k6/http';
import { check } from 'k6';

const PUBLIC_API_HOST = 'api-staging.emporiob2b.com.br';
const PRODUCTION_HOSTS = [
  '://api.emporiob2b.com.br',
  '://emporiob2b.com.br',
  '://www.emporiob2b.com.br',
];

export function env(name, fallback = '') {
  const value = __ENV[name] ?? fallback;
  if (!value) {
    throw new Error(`missing runtime setting: ${name}`);
  }
  return value;
}

export function targetUrl() {
  const value = env('K6_BASE_URL');
  if (PRODUCTION_HOSTS.some((host) => value.includes(host))) {
    throw new Error('production target rejected');
  }
  if (value.startsWith('https://') && !value.includes(PUBLIC_API_HOST)) {
    throw new Error('public target is not the approved staging API');
  }
  return value.replace(/\/+$/, '');
}

export function isPublic() {
  return __ENV.K6_MODE === 'public';
}

export function headers(extra = {}) {
  const result = {
    Accept: 'application/json',
    'Content-Type': 'application/json',
    Origin: env('K6_ORIGIN', 'https://staging.emporiob2b.com.br'),
    ...extra,
  };
  if (isPublic()) {
    result['CF-Access-Client-Id'] = env('K6_ACCESS_CLIENT_ID');
    result['CF-Access-Client-Secret'] = env('K6_ACCESS_CLIENT_SECRET');
  }
  return result;
}

export function login() {
  const response = http.post(
    `${targetUrl()}/api/v1/auth/login`,
    JSON.stringify({
      email: env('K6_LOGIN_EMAIL'),
      senha: env('K6_LOGIN_PASSWORD'),
    }),
    { headers: headers(), tags: { endpoint: 'auth_login' } },
  );
  const valid = check(response, {
    'login succeeds': (res) => res.status === 200,
    'login returns access token': (res) => Boolean(res.json('accessToken')),
  });
  if (!valid) {
    throw new Error(`login failed with status ${response.status}`);
  }
  return response.json('accessToken');
}

export function planStages() {
  if (__ENV.K6_PLAN === 'full') {
    return [
      { target: 1, duration: '60s' },
      { target: 2, duration: '120s' },
      { target: 5, duration: '120s' },
      { target: 10, duration: '120s' },
    ];
  }
  return [
    { target: 1, duration: '30s' },
    { target: 2, duration: '30s' },
  ];
}

export function loadScenario(name) {
  if (__ENV.K6_EXECUTOR === 'constant-vus') {
    const vus = Number(env('K6_VUS'));
    if (!Number.isInteger(vus) || vus < 1) {
      throw new Error('K6_VUS must be a positive integer');
    }
    return {
      executor: 'constant-vus',
      vus,
      duration: env('K6_DURATION'),
      gracefulStop: '5s',
      tags: { load_scenario: name },
    };
  }
  return {
    executor: 'ramping-arrival-rate',
    startRate: 0,
    timeUnit: '1s',
    preAllocatedVUs: 10,
    maxVUs: 50,
    stages: planStages(),
    tags: { load_scenario: name },
  };
}

export function bearerOptions(token, endpoint) {
  return {
    headers: headers({ Authorization: `Bearer ${token}` }),
    tags: { endpoint },
  };
}

export function fixtureMode() {
  return __ENV.K6_FIXTURE_MODE || 'default';
}

export function cnpjFixtures() {
  const raw = __ENV.K6_CNPJS || '';
  if (!raw) {
    if (fixtureMode() === 'all-miss') {
      throw new Error('missing runtime setting: K6_CNPJS');
    }
    return [fixture('K6_CNPJ')];
  }
  const values = raw.split(',').map((value) => value.trim()).filter(Boolean);
  if (values.length === 0 || new Set(values).size !== values.length) {
    throw new Error('K6_CNPJS must contain unique fixtures');
  }
  values.forEach((value) => {
    if (!/^\d{14}$/.test(value)) {
      throw new Error('CNPJ fixture must contain fourteen digits');
    }
  });
  return values;
}

export function cnpjForIteration() {
  const values = cnpjFixtures();
  const offset = Number(__ENV.K6_FIXTURE_OFFSET || 0);
  const durationSeconds = Number(__ENV.K6_DURATION_SECONDS || 0);
  const vuOffset = __ENV.K6_EXECUTOR === 'constant-vus'
    ? (__VU - 1) * durationSeconds
    : 0;
  const index = offset + vuOffset + __ITER;
  if (fixtureMode() === 'all-miss' && index >= values.length) {
    throw new Error('CNPJ fixture pool exhausted');
  }
  return values[index % values.length];
}

export function expectCapacityRejection() {
  return __ENV.K6_EXPECT_CAPACITY_REJECTION === 'true';
}

export function fixture(name) {
  const value = env(name);
  if (name === 'K6_CNPJ' && !/^\d{14}$/.test(value)) {
    throw new Error('CNPJ fixture must contain fourteen digits');
  }
  if (name === 'K6_CEP' && !/^\d{8}$/.test(value)) {
    throw new Error('CEP fixture must contain eight digits');
  }
  return value;
}

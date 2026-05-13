import http from 'k6/http';
import { sleep, check } from 'k6';

export const options = {
  stages: [
    { duration: '5m', target: 100 },    // Ramp up
    { duration: '10m', target: 300 },   // Warm up
    { duration: '45m', target: 600 },   // Sustained high load (good for triggering scaling)
    { duration: '10m', target: 400 },   // Slight reduction
    { duration: '5m', target: 0 },      // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<30000'], // 95% of requests under 30s (adjust as needed)
    http_req_failed: ['rate<0.05'],     // Less than 5% errors
  },
};

const BASE_URL = 'http://localhost:8000'; // Change if needed

export default function () {
  const payload = JSON.stringify({
    model: 'gpt-oss-120b',
    messages: [
      {
        role: 'user',
        content: 'Explain the importance of renewable energy in simple terms.',
      },
    ],
    max_tokens: 256,
    temperature: 0.7,
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
    timeout: '120s', // Important for large models
  };

  const res = http.post(`${BASE_URL}/v1/chat/completions`, payload, params);

  check(res, {
    'status is 200': (r) => r.status === 200,
    'has choices': (r) => r.json('choices') !== undefined,
  });

  // Think time between requests (adjust as needed)
  sleep(1);
}

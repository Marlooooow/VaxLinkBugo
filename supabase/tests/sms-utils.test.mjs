import test from 'node:test';
import assert from 'node:assert/strict';
import {
  maskMobile,
  normalizePhilippineMobile,
  providerResult,
  reminderMessage,
} from '../functions/send-reminder-sms/sms_utils.ts';

test('Philippine mobile numbers are normalized without accepting unrelated formats', () => {
  assert.equal(normalizePhilippineMobile('0912 345 6789'), '639123456789');
  assert.equal(normalizePhilippineMobile('+63 912 345 6789'), '639123456789');
  assert.equal(normalizePhilippineMobile('9123456789'), '639123456789');
  assert.equal(normalizePhilippineMobile('12345'), null);
  assert.equal(maskMobile('639123456789'), '+639******6789');
});

test('reminder copy is specific, compact, and does not claim delivery', () => {
  const message = reminderMessage({
    childName: 'Lia Mendoza',
    vaccineName: 'BCG',
    doseNumber: 1,
    dueOn: '2026-09-02',
  });
  assert.match(message, /^VaxLink Bugo reminder:/);
  assert.match(message, /Lia Mendoza/);
  assert.match(message, /BCG Dose 1/);
  assert.ok(message.length <= 160);
  assert.doesNotMatch(message, /delivered/i);
});

test('Semaphore responses distinguish provider acceptance from failure', () => {
  assert.deepEqual(providerResult(200, [{ message_id: 123, status: 'Queued' }]), {
    accepted: true,
    messageId: '123',
    providerStatus: 'queued',
    failureCode: null,
  });
  assert.deepEqual(providerResult(200, [{ status: 'Failed' }]), {
    accepted: false,
    messageId: null,
    providerStatus: 'failed',
    failureCode: 'PROVIDER_FAILED',
  });
});

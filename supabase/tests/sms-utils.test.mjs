import test from 'node:test';
import assert from 'node:assert/strict';
import {
  maskMobile,
  normalizePhilippineMobile,
  groupedReminderMessage,
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

test('multiple doses for one child are combined into one clear reminder', () => {
  const message = groupedReminderMessage({
    childName: 'Ana Cruz',
    reminders: [
      { vaccineName: 'MMR', doseNumber: 1, dueOn: '2026-10-01', status: 'upcoming' },
      { vaccineName: 'OPV', doseNumber: 2, dueOn: '2026-09-20', status: 'upcoming' },
      { vaccineName: 'BCG', doseNumber: 1, dueOn: '2026-09-01', status: 'overdue' },
    ],
  });
  assert.match(message, /Ana Cruz/);
  assert.match(message, /Overdue: BCG Dose 1 \(Sep 1, 2026\)/);
  assert.match(message, /Upcoming: OPV Dose 2 \(Sep 20, 2026\), MMR Dose 1 \(Oct 1, 2026\)/);
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

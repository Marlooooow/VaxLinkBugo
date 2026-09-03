export function normalizePhilippineMobile(value: string): string | null {
  const digits = value.replace(/\D/g, '')
  if (/^09\d{9}$/.test(digits)) return `63${digits.substring(1)}`
  if (/^9\d{9}$/.test(digits)) return `63${digits}`
  if (/^639\d{9}$/.test(digits)) return digits
  return null
}

export function maskMobile(value: string): string {
  return `+${value.substring(0, 3)}******${value.substring(value.length - 4)}`
}

export function reminderMessage(target: {
  childName: string
  vaccineName: string
  doseNumber: number
  dueOn: string
}): string {
  const due = new Date(`${target.dueOn}T00:00:00Z`).toLocaleDateString('en-PH', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    timeZone: 'Asia/Manila',
  })
  return `VaxLink Bugo reminder: ${target.childName} is due for ${target.vaccineName} Dose ${target.doseNumber} on ${due}. Open VaxLink or contact Bugo Health Center.`
}

export function providerResult(status: number, payload: unknown): {
  accepted: boolean
  messageId: string | null
  providerStatus: string
  failureCode: string | null
} {
  const item = Array.isArray(payload) && payload.length > 0 && payload[0] &&
      typeof payload[0] === 'object' ? payload[0] as Record<string, unknown> : null
  const state = typeof item?.status === 'string' ? item.status.trim().toLowerCase() : ''
  const accepted = status >= 200 && status < 300 && ['queued', 'pending', 'sent'].includes(state)
  return {
    accepted,
    messageId: item?.message_id == null ? null : String(item.message_id),
    providerStatus: state || `http_${status}`,
    failureCode: accepted ? null : (state === 'failed' || state === 'refunded'
      ? `PROVIDER_${state.toUpperCase()}` : `HTTP_${status}`),
  }
}

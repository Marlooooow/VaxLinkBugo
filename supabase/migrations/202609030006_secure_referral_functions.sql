begin;

alter function public.create_referral_group(uuid, text[])
  security definer;
alter function public.record_external_vaccinations(uuid, uuid[], date, text, text, text)
  security definer;

revoke all on function public.create_referral_group(uuid, text[]) from public, anon;
revoke all on function public.record_external_vaccinations(uuid, uuid[], date, text, text, text) from public, anon;
grant execute on function public.create_referral_group(uuid, text[]) to authenticated;
grant execute on function public.record_external_vaccinations(uuid, uuid[], date, text, text, text) to authenticated;

commit;

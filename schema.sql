-- Cole tudo isto no Supabase: SQL Editor > New query > Run
create table if not exists rifa_numeros(
 numero int primary key check(numero between 0 and 99),
 status text not null default 'livre' check(status in ('livre','reservado','vendido')),
 nome text, whatsapp text, pedido uuid, reservado_em timestamptz, pago_em timestamptz);
insert into rifa_numeros(numero) select generate_series(0,99) on conflict do nothing;

alter table rifa_numeros enable row level security;
drop policy if exists admin_all on rifa_numeros;
create policy admin_all on rifa_numeros for all to authenticated using(true) with check(true);

-- Visão pública: só número e status (sem nome/telefone). Reserva vencida (15 min) aparece como livre.
create or replace view numeros_publico as
select numero,
 case when status='reservado' and reservado_em < now()-interval '15 minutes' then 'livre' else status end as status
from rifa_numeros;
grant select on numeros_publico to anon, authenticated;

create or replace function reservar(p_numeros int[], p_nome text, p_whatsapp text) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_pedido uuid := gen_random_uuid(); v_qtd int;
begin
 if p_numeros is null or array_length(p_numeros,1) is null or array_length(p_numeros,1)>10 then raise exception 'invalido'; end if;
 if length(trim(coalesce(p_nome,'')))<2 or length(p_nome)>80 or length(coalesce(p_whatsapp,''))<8 or length(p_whatsapp)>30 then raise exception 'invalido'; end if;
 update rifa_numeros set status='livre',nome=null,whatsapp=null,pedido=null,reservado_em=null
  where status='reservado' and reservado_em < now()-interval '15 minutes';
 with sel as (select numero from rifa_numeros where numero=any(p_numeros) and status='livre' for update)
 select count(*) into v_qtd from sel;
 if v_qtd <> (select count(distinct x) from unnest(p_numeros) x) then raise exception 'indisponivel'; end if;
 update rifa_numeros set status='reservado',nome=trim(p_nome),whatsapp=trim(p_whatsapp),pedido=v_pedido,reservado_em=now()
  where numero=any(p_numeros) and status='livre';
 return v_pedido;
end$$;

create or replace function cancelar(p_pedido uuid) returns void
language sql security definer set search_path=public as $$
 update rifa_numeros set status='livre',nome=null,whatsapp=null,pedido=null,reservado_em=null
  where pedido=p_pedido and status='reservado'; $$;

grant execute on function reservar(int[],text,text), cancelar(uuid) to anon, authenticated;

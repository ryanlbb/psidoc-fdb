-- ryan pimentel

\connect postgres;

drop database if exists psidoc;
drop role if exists psidoc_admin;
drop role if exists psidoc_leitor;

-- cria o banco da clinica em utf-8 pra aceitar acentos
create database psidoc encoding 'UTF8';

\connect psidoc;

set client_encoding = 'UTF8';

-- enums pra travar os campos e nao aceitar valor errado
create type genero as enum ('FEMININO', 'MASCULINO', 'OUTRO');
create type parentesco as enum ('PAI', 'MAE', 'IRMAO', 'IRMA', 'OUTRO');
create type status_agendamento as enum ('AGENDADO', 'CANCELADO', 'CONCLUIDO');
create type status_prontuario as enum ('EM_ATENDIMENTO', 'ENCERRADO');
create type status_pagamento as enum ('PENDENTE', 'PAGO', 'ATRASADO');
create type forma_pagamento as enum ('PIX', 'CREDITO', 'DEBITO', 'DINHEIRO');
create type status_presenca as enum ('PRESENTE', 'AUSENTE');
create type dia_semana as enum ('SEGUNDA', 'TERCA', 'QUARTA', 'QUINTA', 'SEXTA', 'SABADO', 'DOMINGO');

-- tabela de endereco: deixamos separado pra se pessoas da mesma familia morarem juntas nao repetir dado
create table endereco
(
    id_endereco uuid         not null default gen_random_uuid(),
    logradouro  varchar(120) not null,
    numero      varchar(10)  not null,
    complemento varchar(60),
    bairro      varchar(80)  not null,
    municipio   varchar(80)  not null,
    estado      char(2)      not null,
    cep         char(8)      not null,
    constraint pk_endereco primary key (id_endereco),
    -- check pra garantir que o estado tenha 2 letras maiusculas (ex: CE, SP)
    constraint ck_endereco_uf check (estado ~ '^[A-Z]{2}$'),
    -- check pra garantir cep com exatamente 8 digitos numericos sem traco
    constraint ck_endereco_cep check (cep ~ '^[0-9]{8}$')
);

-- tabela de paciente: dados principais de quem se consulta
create table paciente
(
    id_paciente     uuid         not null default gen_random_uuid(),
    id_endereco     uuid         not null,
    nome            varchar(120) not null,
    data_nascimento date         not null,
    telefone        varchar(20),
    cpf             char(11)     not null,
    esta_ativo      boolean      not null default true,
    genero          genero       not null,
    constraint pk_paciente primary key (id_paciente),
    -- cpf unico por paciente no sistema
    constraint uq_paciente_cpf unique (cpf),
    -- check pra validar que o cpf tem 11 numeros
    constraint ck_paciente_cpf check (cpf ~ '^[0-9]{11}$'),
    -- check pra impedir data de nascimento absurda antes de 1900
    constraint ck_paciente_nascimento check (data_nascimento >= date '1900-01-01'),
    -- se tentar apagar o endereco em uso, o restrict bloqueia pra nao quebrar integridade
    constraint fk_paciente_endereco foreign key (id_endereco)
        references endereco (id_endereco) on delete restrict
);

-- prontuario: relacao 1 pra 1, cada paciente so tem um prontuario
create table prontuario
(
    id_prontuario  uuid              not null default gen_random_uuid(),
    id_paciente    uuid              not null,
    status         status_prontuario not null default 'EM_ATENDIMENTO',
    renda_familiar numeric(10, 2),
    observacoes    text,
    constraint pk_prontuario primary key (id_prontuario),
    -- unique no id_paciente garante que nao tem como criar dois prontuarios pro mesmo paciente
    constraint uq_prontuario_paciente unique (id_paciente),
    -- check: renda nao pode ser negativa
    constraint ck_prontuario_renda check (renda_familiar is null or renda_familiar >= 0),
    constraint fk_prontuario_paciente foreign key (id_paciente)
        references paciente (id_paciente) on delete restrict
);

-- responsavel legal: dados dos pais ou tutores quando o paciente for crianca ou adolescente
create table responsavel_legal
(
    id_responsavel  uuid         not null default gen_random_uuid(),
    id_endereco     uuid         not null,
    nome            varchar(120) not null,
    data_nascimento date         not null,
    telefone        varchar(20),
    cpf             char(11)     not null,
    email           varchar(254),
    constraint pk_responsavel_legal primary key (id_responsavel),
    constraint uq_responsavel_cpf unique (cpf),
    constraint ck_responsavel_cpf check (cpf ~ '^[0-9]{11}$'),
    constraint fk_responsavel_endereco foreign key (id_endereco)
        references endereco (id_endereco) on delete restrict
);

-- vinculo entre paciente e responsavel: n pra m pq um paciente pode ter pai e mae, e um pai pode ter mais de um filho cadastrado
create table vinculo_paciente_responsavel
(
    id_paciente    uuid       not null,
    id_responsavel uuid       not null,
    parentesco     parentesco not null,
    -- chave primaria composta pelos dois ids pra nao cadastrar o mesmo vinculo duplicado
    constraint pk_vinculo_paciente_responsavel primary key (id_paciente, id_responsavel),
    -- se o paciente ou responsavel for excluido, apaga a ligacao em cascata
    constraint fk_vpr_paciente foreign key (id_paciente)
        references paciente (id_paciente) on delete cascade,
    constraint fk_vpr_responsavel foreign key (id_responsavel)
        references responsavel_legal (id_responsavel) on delete cascade
);

-- ryan lopes

-- tabela base de usuario: qualquer um que loga no sistema (email, cpf e senha)
create table usuario
(
    id_usuario    uuid         not null default gen_random_uuid(),
    nome          varchar(120) not null,
    email         varchar(254) not null,
    cpf           char(11)     not null,
    telefone      varchar(20),
    senha         varchar(100) not null,
    esta_ativo    boolean      not null default true,
    criado_em     timestamptz  not null default now(),
    atualizado_em timestamptz  not null default now(),
    constraint pk_usuario primary key (id_usuario),
    constraint uq_usuario_cpf unique (cpf),
    constraint ck_usuario_cpf check (cpf ~ '^[0-9]{11}$'),
    -- check com regex pra validar formato basico de email (algo@dominio.com)
    constraint ck_usuario_email check (email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')
);

-- indice unico com lower(email) pra ninguem cadastrar o mesmo email so trocando maiuscula por minuscula
create unique index uq_usuario_email on usuario (lower(email));

-- psicologo: especializacao de usuario, herda da tabela usuario e guarda o crp
create table psicologo
(
    id_usuario uuid        not null,
    numero_crp varchar(20) not null,
    constraint pk_psicologo primary key (id_usuario),
    -- crp unico por psicologo
    constraint uq_psicologo_crp unique (numero_crp),
    -- se o usuario for apagado, o psicologo e removido em cascata
    constraint fk_psicologo_usuario foreign key (id_usuario)
        references usuario (id_usuario) on delete cascade
);

-- gestor: quem cuida da clinica, tb especializa usuario
create table gestor
(
    id_usuario uuid not null,
    constraint pk_gestor primary key (id_usuario),
    constraint fk_gestor_usuario foreign key (id_usuario)
        references usuario (id_usuario) on delete cascade
);

-- catalogo de especialidades que a clinica atende
create table especialidade
(
    id_especialidade uuid        not null default gen_random_uuid(),
    nome             varchar(80) not null,
    constraint pk_especialidade primary key (id_especialidade),
    constraint uq_especialidade_nome unique (nome)
);

-- vinculo entre psicologo e especialidade: n pra m pq um psicologo pode ter varias especialidades
create table vinculo_especialidade_psicologo
(
    id_vinculo_especialidade uuid not null default gen_random_uuid(),
    id_especialidade         uuid not null,
    id_psicologo             uuid not null,
    constraint pk_vinculo_especialidade_psicologo primary key (id_vinculo_especialidade),
    -- unique no par pra nao vincular a mesma especialidade duas vezes pro mesmo psicologo
    constraint uq_vinculo_especialidade_psicologo unique (id_especialidade, id_psicologo),
    constraint fk_vep_especialidade foreign key (id_especialidade)
        references especialidade (id_especialidade) on delete restrict,
    constraint fk_vep_psicologo foreign key (id_psicologo)
        references psicologo (id_usuario) on delete restrict
);

-- disponibilidade da agenda: os dias e turnos que o psicologo trabalha na clinica
create table disponibilidade_agenda
(
    id_disponibilidade uuid       not null default gen_random_uuid(),
    id_psicologo       uuid       not null,
    dia_semana         dia_semana not null,
    janela_hora_inicio time       not null,
    janela_hora_fim    time       not null,
    constraint pk_disponibilidade_agenda primary key (id_disponibilidade),
    -- unique pra nao duplicar a mesma janela no mesmo dia pro psicologo
    constraint uq_disponibilidade_janela unique (id_psicologo, dia_semana, janela_hora_inicio),
    -- check: garante que o fim do expediente seja depois do inicio
    constraint ck_disponibilidade_janela check (janela_hora_fim > janela_hora_inicio),
    constraint fk_disponibilidade_psicologo foreign key (id_psicologo)
        references psicologo (id_usuario) on delete restrict
);

-- vinculo entre psicologo e paciente: o tratamento continuo deles
create table vinculo_psicologo_paciente
(
    id_vinculo          uuid not null default gen_random_uuid(),
    id_psicologo        uuid not null,
    id_paciente         uuid not null,
    data_inicio         date not null,
    data_fim            date,
    motivo_encerramento text,
    constraint pk_vinculo_psicologo_paciente primary key (id_vinculo),
    constraint uq_vpp_periodo unique (id_psicologo, id_paciente, data_inicio),
    -- check: se tiver data de fim, nao pode ser antes do inicio
    constraint ck_vpp_periodo check (data_fim is null or data_fim >= data_inicio),
    -- check: so pode preencher motivo de encerramento se a data fim tiver preenchida
    constraint ck_vpp_motivo check (data_fim is not null or motivo_encerramento is null),
    constraint fk_vpp_psicologo foreign key (id_psicologo)
        references psicologo (id_usuario) on delete restrict,
    constraint fk_vpp_paciente foreign key (id_paciente)
        references paciente (id_paciente) on delete restrict
);

-- agendamento: marca a consulta cruzando paciente, psicologo e especialidade
create table agendamento
(
    id_agendamento           uuid               not null default gen_random_uuid(),
    id_paciente              uuid               not null,
    id_disponibilidade       uuid               not null,
    id_vinculo_especialidade uuid               not null,
    valor_cobrado            numeric(10, 2)     not null,
    data_agendamento         date               not null,
    hora_inicio              time               not null,
    hora_fim                 time               not null,
    status_agendamento       status_agendamento not null default 'AGENDADO',
    cancelado_em             timestamptz,
    constraint pk_agendamento primary key (id_agendamento),
    -- check: valor da consulta nao pode ser negativo
    constraint ck_agendamento_valor check (valor_cobrado >= 0),
    -- check: hora fim maior que hora inicio
    constraint ck_agendamento_horario check (hora_fim > hora_inicio),
    -- check de consistencia: so pode ter data de cancelamento se tiver cancelado e vice-versa
    constraint ck_agendamento_cancelamento
        check ((status_agendamento = 'CANCELADO') = (cancelado_em is not null)),
    constraint fk_agendamento_paciente foreign key (id_paciente)
        references paciente (id_paciente) on delete restrict,
    constraint fk_agendamento_disponibilidade foreign key (id_disponibilidade)
        references disponibilidade_agenda (id_disponibilidade) on delete restrict,
    constraint fk_agendamento_vinculo_especialidade foreign key (id_vinculo_especialidade)
        references vinculo_especialidade_psicologo (id_vinculo_especialidade) on delete restrict
);

-- pagamento: controle da cobranca (pix, dinheiro, cartao)
create table pagamento
(
    id_pagamento        uuid             not null default gen_random_uuid(),
    id_agendamento      uuid             not null,
    forma_pagamento     forma_pagamento  not null,
    status_pagamento    status_pagamento not null default 'PENDENTE',
    quantidade_parcelas integer          not null default 1,
    data_pagamento      timestamptz,
    constraint pk_pagamento primary key (id_pagamento),
    -- cada agendamento so tem uma cobranca associada
    constraint uq_pagamento_agendamento unique (id_agendamento),
    -- check: maximo de 12 parcelas
    constraint ck_pagamento_parcelas check (quantidade_parcelas between 1 and 12),
    -- check: parcelamento acima de 1 vez so e permitido no cartao de credito
    constraint ck_pagamento_parcelas_forma
        check (forma_pagamento = 'CREDITO' or quantidade_parcelas = 1),
    -- check: so pode ter data de pagamento se o status for PAGO
    constraint ck_pagamento_data
        check ((status_pagamento = 'PAGO') = (data_pagamento is not null)),
    constraint fk_pagamento_agendamento foreign key (id_agendamento)
        references agendamento (id_agendamento) on delete restrict
);

-- sessao: se o paciente veio ou faltou, com justificativa se faltou
create table sessao_atendimento
(
    id_sessao           uuid            not null default gen_random_uuid(),
    id_agendamento      uuid            not null,
    inicio_real         timestamptz,
    fim_real            timestamptz,
    status_presenca     status_presenca not null,
    justificativa_falta varchar(255),
    constraint pk_sessao_atendimento primary key (id_sessao),
    constraint uq_sessao_agendamento unique (id_agendamento),
    -- check: horario real de fim maior ou igual ao de inicio
    constraint ck_sessao_periodo check (fim_real is null or inicio_real is null or fim_real >= inicio_real),
    -- check: se o paciente esteve presente, os horarios reais de inicio e fim sao obrigatorios
    constraint ck_sessao_presente
        check (status_presenca = 'AUSENTE' or (inicio_real is not null and fim_real is not null)),
    -- check: justificativa de falta so quando ausente
    constraint ck_sessao_justificativa
        check (status_presenca = 'AUSENTE' or justificativa_falta is null),
    constraint fk_sessao_agendamento foreign key (id_agendamento)
        references agendamento (id_agendamento) on delete restrict
);

-- evolucao: o que o psicologo anotou sobre a sessao
create table evolucao_psicologica
(
    id_evolucao    uuid not null default gen_random_uuid(),
    id_sessao      uuid not null,
    texto_evolucao text not null,
    constraint pk_evolucao_psicologica primary key (id_evolucao),
    constraint uq_evolucao_sessao unique (id_sessao),
    -- check: impede salvar evolucao vazia ou so com espaco em branco
    constraint ck_evolucao_texto check (length(btrim(texto_evolucao)) > 0),
    constraint fk_evolucao_sessao foreign key (id_sessao)
        references sessao_atendimento (id_sessao) on delete restrict
);

-- usuarios do banco
create role psidoc_admin login password 'admin'
    nosuperuser nocreatedb nocreaterole noreplication nobypassrls;

create role psidoc_leitor login password 'leitor'
    nosuperuser nocreatedb nocreaterole noreplication nobypassrls;

-- passa a posse oficial do banco pro admin
revoke all on database psidoc from public;
alter database psidoc owner to psidoc_admin;
alter schema public owner to psidoc_admin;

-- permissoes do leitor
grant connect on database psidoc to psidoc_leitor;
revoke all on schema public from public;
grant usage on schema public to psidoc_leitor;
grant select on all tables in schema public to psidoc_leitor;

-- protecao onde o leitor nao pode ver a coluna de senha da tabela usuario
revoke select on usuario from psidoc_leitor;
grant select (id_usuario, nome, email, cpf, telefone, esta_ativo, criado_em, atualizado_em)
    on usuario to psidoc_leitor;

alter default privileges for role psidoc_admin in schema public
    grant select on tables to psidoc_leitor;

alter role psidoc_leitor set default_transaction_read_only = on;

-- guilherme marques

-- indices pra acelerar busca e join nas colunas mais consultadas
create index idx_vep_psicologo on vinculo_especialidade_psicologo (id_psicologo);
create index idx_paciente_endereco on paciente (id_endereco);
create index idx_responsavel_endereco on responsavel_legal (id_endereco);
create index idx_vpr_responsavel on vinculo_paciente_responsavel (id_responsavel);
create index idx_vpp_paciente on vinculo_psicologo_paciente (id_paciente);
create index idx_agendamento_paciente on agendamento (id_paciente, data_agendamento);
create index idx_agendamento_disponibilidade on agendamento (id_disponibilidade);
create index idx_agendamento_vinculo on agendamento (id_vinculo_especialidade);
create index idx_agendamento_data on agendamento (data_agendamento);

-- indice parcial pra buscar rapido quem ta devendo (indexa so o que nao ta pago)
create index idx_pagamento_em_aberto on pagamento (status_pagamento)
    where status_pagamento <> 'PAGO';

-- indice unico parcial: nao deixa ter dois tratamentos abertos ao mesmo tempo pro mesmo paciente e psicologo
create unique index uq_vpp_vinculo_aberto
    on vinculo_psicologo_paciente (id_psicologo, id_paciente)
    where data_fim is null;

-- indice unico parcial: impede dois agendamentos no mesmo horario, mas libera a vaga se tiver cancelado
create unique index uq_agendamento_sem_conflito
    on agendamento (id_disponibilidade, data_agendamento, hora_inicio)
    where status_agendamento <> 'CANCELADO';

-- trigger 1: atualiza o atualizado_em com a data atual toda vez que der update no usuario
create function fn_usuario_atualizado_em() returns trigger
    language plpgsql as
$$
begin
    new.atualizado_em := now();
    return new;
end;
$$;

create trigger trg_usuario_atualizado_em
    before update
    on usuario
    for each row
execute function fn_usuario_atualizado_em();

-- trigger 2: especializacao total de usuario - garante que todo usuario seja psicologo ou gestor
-- usamos deferrable initially deferred pra esperar o commit da transacao, pq nao da pra inserir nas duas tabelas ao mesmo tempo
create function fn_usuario_total() returns trigger
    language plpgsql as
$$
begin
    if not exists (select 1 from psicologo where id_usuario = new.id_usuario)
        and not exists (select 1 from gestor where id_usuario = new.id_usuario) then
        raise exception 'usuario % precisa ser psicologo e/ou gestor (especializacao total)',
            new.id_usuario using errcode = '23514';
    end if;
    return null;
end;
$$;

create constraint trigger trg_usuario_total
    after insert
    on usuario
    deferrable initially deferred
    for each row
execute function fn_usuario_total();

-- trigger 3: valida a agenda antes de salvar
-- confere se o psicologo da disponibilidade é o mesmo da especialidade,
-- se o dia da semana bate com a data usando isodow e se o horario cabe na jornada dele
create function fn_agendamento_valida() returns trigger
    language plpgsql as
$$
declare
    v_psi_disp uuid;
    v_dia      dia_semana;
    v_ini      time;
    v_fim      time;
    v_psi_esp  uuid;
    v_dias     text[] := array ['SEGUNDA','TERCA','QUARTA','QUINTA','SEXTA','SABADO','DOMINGO'];
begin
    select id_psicologo, dia_semana, janela_hora_inicio, janela_hora_fim
    into v_psi_disp, v_dia, v_ini, v_fim
    from disponibilidade_agenda
    where id_disponibilidade = new.id_disponibilidade;

    select id_psicologo
    into v_psi_esp
    from vinculo_especialidade_psicologo
    where id_vinculo_especialidade = new.id_vinculo_especialidade;

    if v_psi_disp is distinct from v_psi_esp then
        raise exception 'disponibilidade e especialidade pertencem a psicologos diferentes'
            using errcode = '23514';
    end if;

    if v_dias[extract(isodow from new.data_agendamento)::int] <> v_dia::text then
        raise exception 'a data % nao cai em %', new.data_agendamento, v_dia
            using errcode = '23514';
    end if;

    if new.hora_inicio < v_ini or new.hora_fim > v_fim then
        raise exception 'horario %-% fora da janela de disponibilidade %-%',
            new.hora_inicio, new.hora_fim, v_ini, v_fim using errcode = '23514';
    end if;

    return new;
end;
$$;

create trigger trg_agendamento_valida
    before insert or update of id_disponibilidade, id_vinculo_especialidade,
        data_agendamento, hora_inicio, hora_fim
    on agendamento
    for each row
execute function fn_agendamento_valida();

-- visao 1: agenda com 10 tabelas juntas pra recepcao da clinica ver tudo de uma vez
create view v_agenda_detalhada as
select a.id_agendamento,
       a.data_agendamento,
       d.dia_semana,
       a.hora_inicio,
       a.hora_fim,
       a.status_agendamento,
       pac.id_paciente,
       pac.nome                     as paciente,
       ps.id_usuario                as id_psicologo,
       up.nome                      as psicologo,
       ps.numero_crp,
       esp.nome                     as especialidade,
       a.valor_cobrado,
       s.status_presenca,
       (ev.id_evolucao is not null) as possui_evolucao,
       pg.forma_pagamento,
       pg.status_pagamento,
       pg.quantidade_parcelas,
       pg.data_pagamento
from agendamento a
         join paciente pac on pac.id_paciente = a.id_paciente
         join disponibilidade_agenda d on d.id_disponibilidade = a.id_disponibilidade
         join vinculo_especialidade_psicologo vep on vep.id_vinculo_especialidade = a.id_vinculo_especialidade
         join especialidade esp on esp.id_especialidade = vep.id_especialidade
         join psicologo ps on ps.id_usuario = vep.id_psicologo
         join usuario up on up.id_usuario = ps.id_usuario
         left join sessao_atendimento s on s.id_agendamento = a.id_agendamento
         left join evolucao_psicologica ev on ev.id_sessao = s.id_sessao
         left join pagamento pg on pg.id_agendamento = a.id_agendamento;

comment on view v_agenda_detalhada is
    'agenda completa: agendamento + paciente + psicologo + especialidade + sessao + evolucao + pagamento.';

-- visao 2: financeiro do mes pra ver faturamento, faltas e inadimplencia por psicologo
create view v_financeiro_mensal_psicologo as
select v.id_psicologo,
       v.psicologo,
       date_trunc('month', v.data_agendamento)::date                                     as mes_referencia,
       count(*) filter (where v.status_agendamento = 'CONCLUIDO')                        as sessoes_concluidas,
       count(*) filter (where v.status_agendamento = 'CANCELADO')                        as sessoes_canceladas,
       coalesce(sum(v.valor_cobrado) filter (where v.status_pagamento = 'PAGO'), 0)      as valor_recebido,
       coalesce(sum(v.valor_cobrado) filter (where v.status_pagamento = 'PENDENTE'), 0)  as valor_pendente,
       coalesce(sum(v.valor_cobrado) filter (where v.status_pagamento = 'ATRASADO'), 0)  as valor_atrasado,
       round(avg(v.valor_cobrado) filter (where v.status_agendamento <> 'CANCELADO'), 2) as ticket_medio,
       round(100.0 * coalesce(sum(v.valor_cobrado) filter (where v.status_pagamento = 'PAGO'), 0)
                 / nullif(sum(v.valor_cobrado) filter (where v.status_pagamento is not null), 0), 1)
                                                                                         as percentual_recebido
from v_agenda_detalhada v
group by v.id_psicologo, v.psicologo, date_trunc('month', v.data_agendamento);

comment on view v_financeiro_mensal_psicologo is
    'fechamento financeiro mensal por psicologo (recebido, pendente, atrasado, ticket medio).';

-- passa a posse de tudo pro admin
do
$$
    declare
        r record;
    begin
        for r in select c.relname,
                        case c.relkind when 'v' then 'VIEW' else 'TABLE' end as tipo
                 from pg_class c
                          join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'public'
                   and c.relkind in ('r', 'v', 'p')
            loop
                execute format('alter %s public.%I owner to psidoc_admin', r.tipo, r.relname);
            end loop;

        for r in select t.typname
                 from pg_type t
                          join pg_namespace n on n.oid = t.typnamespace
                 where n.nspname = 'public'
                   and t.typtype = 'e'
            loop
                execute format('alter type public.%I owner to psidoc_admin', r.typname);
            end loop;

        for r in select p.oid::regprocedure as assinatura
                 from pg_proc p
                          join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public'
                   and not exists (select 1
                                   from pg_depend d
                                   where d.objid = p.oid
                                     and d.deptype = 'e')
            loop
                execute format('alter function %s owner to psidoc_admin', r.assinatura);
            end loop;
    end
$$;

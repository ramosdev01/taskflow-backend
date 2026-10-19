-- Esquema inicial de TaskFlow v1 (esquema-backend.md §1 y §9).
-- Los textos libres son `text`: sus límites (ADR-004) se validan en el servicio.
-- Los id y las marcas de tiempo no tienen DEFAULT: los fija la aplicación (Hibernate y el Clock).

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ---------------------------------------------------------------------------
-- Usuarios y tokens
-- ---------------------------------------------------------------------------

CREATE TABLE users (
    id                    uuid         NOT NULL,
    name                  text         NOT NULL,
    email                 varchar(254) NOT NULL,
    password_hash         text,
    account_provider      varchar(30)  NOT NULL,
    google_id             text,
    job_title             text,
    url_avatar            text,
    email_verified_at     timestamptz,
    account_state         varchar(30)  NOT NULL,
    created_at            timestamptz  NOT NULL,
    updated_at            timestamptz  NOT NULL,
    deletion_requested_at timestamptz,
    deleted_at            timestamptz,
    CONSTRAINT pk_users PRIMARY KEY (id),
    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT uq_users_google_id UNIQUE (google_id),
    CONSTRAINT ck_users_account_provider CHECK (account_provider IN ('GOOGLE', 'LOCAL')),
    CONSTRAINT ck_users_account_state CHECK (account_state IN ('ACTIVE', 'PENDING_DELETION', 'DELETED'))
);

CREATE TABLE email_verification_token (
    id         uuid        NOT NULL,
    user_id    uuid        NOT NULL,
    token_hash char(64)    NOT NULL,
    expires_at timestamptz NOT NULL,
    used_at    timestamptz,
    created_at timestamptz NOT NULL,
    CONSTRAINT pk_email_verification_token PRIMARY KEY (id),
    CONSTRAINT uq_email_verification_token_hash UNIQUE (token_hash),
    CONSTRAINT fk_email_verification_token_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);
CREATE INDEX ix_email_verification_token_user ON email_verification_token (user_id);

CREATE TABLE password_reset_token (
    id         uuid        NOT NULL,
    user_id    uuid        NOT NULL,
    token_hash char(64)    NOT NULL,
    expires_at timestamptz NOT NULL,
    used_at    timestamptz,
    created_at timestamptz NOT NULL,
    CONSTRAINT pk_password_reset_token PRIMARY KEY (id),
    CONSTRAINT uq_password_reset_token_hash UNIQUE (token_hash),
    CONSTRAINT fk_password_reset_token_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);
CREATE INDEX ix_password_reset_token_user ON password_reset_token (user_id);

CREATE TABLE refresh_token (
    id             uuid        NOT NULL,
    user_id        uuid        NOT NULL,
    token_hash     char(64)    NOT NULL,
    expires_at     timestamptz NOT NULL,
    revoked_at     timestamptz,
    replaced_by_id uuid,
    created_at     timestamptz NOT NULL,
    CONSTRAINT pk_refresh_token PRIMARY KEY (id),
    CONSTRAINT uq_refresh_token_hash UNIQUE (token_hash),
    CONSTRAINT fk_refresh_token_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    -- La limpieza de tokens borra los viejos de la cadena de rotación
    CONSTRAINT fk_refresh_token_replaced_by FOREIGN KEY (replaced_by_id) REFERENCES refresh_token (id) ON DELETE SET NULL
);
CREATE INDEX ix_refresh_token_user ON refresh_token (user_id);

-- ---------------------------------------------------------------------------
-- Tableros, miembros e invitaciones
-- ---------------------------------------------------------------------------

CREATE TABLE board (
    id               uuid        NOT NULL,
    name             text        NOT NULL,
    description      text,
    color            varchar(7)  NOT NULL,
    owner_id         uuid        NOT NULL,
    version          integer     NOT NULL,
    created_at       timestamptz NOT NULL,
    updated_at       timestamptz NOT NULL,
    last_activity_at timestamptz NOT NULL,
    CONSTRAINT pk_board PRIMARY KEY (id),
    -- Sin cascada: los usuarios no se borran, se anonimizan (ADR-009)
    CONSTRAINT fk_board_owner FOREIGN KEY (owner_id) REFERENCES users (id)
);

CREATE TABLE board_member (
    id        uuid        NOT NULL,
    board_id  uuid        NOT NULL,
    user_id   uuid        NOT NULL,
    role      varchar(30) NOT NULL,
    joined_at timestamptz NOT NULL,
    CONSTRAINT pk_board_member PRIMARY KEY (id),
    CONSTRAINT uq_board_member_board_user UNIQUE (board_id, user_id),
    CONSTRAINT fk_board_member_board FOREIGN KEY (board_id) REFERENCES board (id) ON DELETE CASCADE,
    CONSTRAINT fk_board_member_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT ck_board_member_role CHECK (role IN ('OWNER', 'ADMIN', 'MEMBER'))
);
CREATE UNIQUE INDEX uq_board_member_owner ON board_member (board_id) WHERE role = 'OWNER';
CREATE INDEX ix_board_member_user ON board_member (user_id);

CREATE TABLE board_invitation (
    id                 uuid        NOT NULL,
    board_id           uuid        NOT NULL,
    invited_user_id    uuid        NOT NULL,
    invited_by_user_id uuid        NOT NULL,
    status             varchar(30) NOT NULL,
    expires_at         timestamptz NOT NULL,
    created_at         timestamptz NOT NULL,
    CONSTRAINT pk_board_invitation PRIMARY KEY (id),
    CONSTRAINT fk_board_invitation_board FOREIGN KEY (board_id) REFERENCES board (id) ON DELETE CASCADE,
    CONSTRAINT fk_board_invitation_invited_user FOREIGN KEY (invited_user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_board_invitation_invited_by FOREIGN KEY (invited_by_user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT ck_board_invitation_status CHECK (status IN ('PENDING', 'ACCEPTED', 'REJECTED', 'EXPIRED', 'CANCELED'))
);
CREATE UNIQUE INDEX uq_board_invitation_pending ON board_invitation (board_id, invited_user_id) WHERE status = 'PENDING';
CREATE INDEX ix_board_invitation_invited_status ON board_invitation (invited_user_id, status);

-- ---------------------------------------------------------------------------
-- Columnas, tareas y subtareas (posiciones con separación de 1000, ADR-001)
-- ---------------------------------------------------------------------------

CREATE TABLE board_column (
    id         uuid    NOT NULL,
    board_id   uuid    NOT NULL,
    name       text    NOT NULL,
    position   integer NOT NULL,
    task_limit integer NOT NULL DEFAULT 50,
    CONSTRAINT pk_board_column PRIMARY KEY (id),
    -- Diferible para poder rebalancear o intercambiar posiciones en una transacción
    CONSTRAINT uq_board_column_position UNIQUE (board_id, position) DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_board_column_board FOREIGN KEY (board_id) REFERENCES board (id) ON DELETE CASCADE,
    CONSTRAINT ck_board_column_task_limit CHECK (task_limit BETWEEN 1 AND 100)
);

CREATE TABLE task (
    id           uuid        NOT NULL,
    board_id     uuid        NOT NULL,
    column_id    uuid,
    assignee_id  uuid,
    title        text        NOT NULL,
    description  text,
    is_done      boolean     NOT NULL DEFAULT false,
    completed_at timestamptz,
    start_date   date,
    due_date     date,
    priority     varchar(30) NOT NULL DEFAULT 'MEDIUM',
    position     integer,
    version      integer     NOT NULL,
    created_at   timestamptz NOT NULL,
    updated_at   timestamptz NOT NULL,
    CONSTRAINT pk_task PRIMARY KEY (id),
    CONSTRAINT uq_task_position UNIQUE (column_id, position) DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_task_board FOREIGN KEY (board_id) REFERENCES board (id) ON DELETE CASCADE,
    -- Borrar una columna borra sus tareas (TRD §3); las completadas no tienen columna
    CONSTRAINT fk_task_column FOREIGN KEY (column_id) REFERENCES board_column (id) ON DELETE CASCADE,
    CONSTRAINT fk_task_assignee FOREIGN KEY (assignee_id) REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT ck_task_priority CHECK (priority IN ('LOW', 'MEDIUM', 'HIGH', 'URGENT')),
    -- Una tarea completada sale del kanban (ADR-011)
    CONSTRAINT ck_task_done_state CHECK (
        (NOT is_done AND column_id IS NOT NULL AND position IS NOT NULL)
        OR (is_done AND column_id IS NULL AND position IS NULL AND completed_at IS NOT NULL)
    ),
    CONSTRAINT ck_task_dates CHECK (start_date IS NULL OR due_date IS NULL OR start_date <= due_date)
);
CREATE INDEX ix_task_board ON task (board_id);
CREATE INDEX ix_task_assignee_due_date ON task (assignee_id, due_date);
CREATE INDEX ix_task_board_completed ON task (board_id, completed_at) WHERE is_done;

CREATE TABLE subtask (
    id       uuid    NOT NULL,
    task_id  uuid    NOT NULL,
    title    text    NOT NULL,
    is_done  boolean NOT NULL DEFAULT false,
    position integer NOT NULL,
    CONSTRAINT pk_subtask PRIMARY KEY (id),
    CONSTRAINT uq_subtask_position UNIQUE (task_id, position) DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_subtask_task FOREIGN KEY (task_id) REFERENCES task (id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------------
-- Comentarios y menciones
-- ---------------------------------------------------------------------------

CREATE TABLE comment (
    id         uuid        NOT NULL,
    task_id    uuid        NOT NULL,
    author_id  uuid        NOT NULL,
    content    text        NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    CONSTRAINT pk_comment PRIMARY KEY (id),
    CONSTRAINT fk_comment_task FOREIGN KEY (task_id) REFERENCES task (id) ON DELETE CASCADE,
    -- Sin cascada: los comentarios se conservan al anonimizar al autor (ADR-009)
    CONSTRAINT fk_comment_author FOREIGN KEY (author_id) REFERENCES users (id)
);
CREATE INDEX ix_comment_task_created ON comment (task_id, created_at);

CREATE TABLE comment_mention (
    comment_id        uuid NOT NULL,
    mentioned_user_id uuid NOT NULL,
    CONSTRAINT pk_comment_mention PRIMARY KEY (comment_id, mentioned_user_id),
    CONSTRAINT fk_comment_mention_comment FOREIGN KEY (comment_id) REFERENCES comment (id) ON DELETE CASCADE,
    CONSTRAINT fk_comment_mention_user FOREIGN KEY (mentioned_user_id) REFERENCES users (id) ON DELETE CASCADE
);
CREATE INDEX ix_comment_mention_user ON comment_mention (mentioned_user_id);

-- ---------------------------------------------------------------------------
-- Etiquetas
-- ---------------------------------------------------------------------------

CREATE TABLE tag (
    id       uuid       NOT NULL,
    board_id uuid       NOT NULL,
    name     text       NOT NULL,
    color    varchar(7) NOT NULL,
    CONSTRAINT pk_tag PRIMARY KEY (id),
    CONSTRAINT fk_tag_board FOREIGN KEY (board_id) REFERENCES board (id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX uq_tag_board_name ON tag (board_id, lower(name));

CREATE TABLE task_tag (
    task_id uuid NOT NULL,
    tag_id  uuid NOT NULL,
    CONSTRAINT pk_task_tag PRIMARY KEY (task_id, tag_id),
    CONSTRAINT fk_task_tag_task FOREIGN KEY (task_id) REFERENCES task (id) ON DELETE CASCADE,
    CONSTRAINT fk_task_tag_tag FOREIGN KEY (tag_id) REFERENCES tag (id) ON DELETE CASCADE
);
CREATE INDEX ix_task_tag_tag ON task_tag (tag_id);

-- ---------------------------------------------------------------------------
-- Notificaciones (ADR-008)
-- ---------------------------------------------------------------------------

CREATE TABLE notification (
    id            uuid        NOT NULL,
    user_id       uuid        NOT NULL,
    type          varchar(30) NOT NULL,
    actor_id      uuid,
    board_id      uuid,
    task_id       uuid,
    comment_id    uuid,
    invitation_id uuid,
    payload       jsonb       NOT NULL,
    dedupe_key    text,
    read_at       timestamptz,
    created_at    timestamptz NOT NULL,
    CONSTRAINT pk_notification PRIMARY KEY (id),
    CONSTRAINT fk_notification_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    -- El payload conserva los textos si el origen se elimina
    CONSTRAINT fk_notification_actor FOREIGN KEY (actor_id) REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT fk_notification_board FOREIGN KEY (board_id) REFERENCES board (id) ON DELETE SET NULL,
    CONSTRAINT fk_notification_task FOREIGN KEY (task_id) REFERENCES task (id) ON DELETE SET NULL,
    CONSTRAINT fk_notification_comment FOREIGN KEY (comment_id) REFERENCES comment (id) ON DELETE SET NULL,
    CONSTRAINT fk_notification_invitation FOREIGN KEY (invitation_id) REFERENCES board_invitation (id) ON DELETE SET NULL,
    CONSTRAINT ck_notification_type CHECK (type IN (
        'TASK_ASSIGNED', 'MENTION', 'INVITATION_RECEIVED', 'INVITATION_ACCEPTED', 'INVITATION_REJECTED',
        'ROLE_CHANGED', 'REMOVED_FROM_BOARD', 'OWNERSHIP_TRANSFERRED',
        'DUE_SOON', 'DUE_TODAY', 'OVERDUE', 'WEEKLY_DIGEST'
    ))
);
CREATE INDEX ix_notification_feed ON notification (user_id, read_at, created_at DESC);
-- Recordatorios y resúmenes idempotentes (ADR-008)
CREATE UNIQUE INDEX uq_notification_dedupe ON notification (user_id, type, dedupe_key) WHERE dedupe_key IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Búsqueda por coincidencia parcial (ADR-013)
-- ---------------------------------------------------------------------------

CREATE INDEX ix_task_title_trgm ON task USING gin (title gin_trgm_ops);
CREATE INDEX ix_task_description_trgm ON task USING gin (description gin_trgm_ops);
CREATE INDEX ix_comment_content_trgm ON comment USING gin (content gin_trgm_ops);
CREATE INDEX ix_tag_name_trgm ON tag USING gin (name gin_trgm_ops);

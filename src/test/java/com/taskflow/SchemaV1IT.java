package com.taskflow;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;

/**
 * Restricciones de {@code V1__init.sql} (esquema-backend.md §1 y §9). Cada prueba hace rollback; las restricciones
 * diferidas se comprueban con {@code SET CONSTRAINTS ALL IMMEDIATE}, que adelanta el chequeo del commit.
 */
@SpringBootTest
@Import(TestcontainersConfiguration.class)
@Transactional
class SchemaV1IT {

    private static final OffsetDateTime NOW = OffsetDateTime.parse("2026-10-16T12:00:00Z");

    @Autowired
    JdbcTemplate jdbc;

    @Test
    void flywayAppliesV1WithPgTrgmAndAllTables() {
        assertThat(jdbc.queryForObject("SELECT success FROM flyway_schema_history WHERE version = '1'", Boolean.class))
                .isTrue();
        assertThat(jdbc.queryForObject("SELECT count(*) FROM pg_extension WHERE extname = 'pg_trgm'", Integer.class))
                .isEqualTo(1);
        assertThat(jdbc.queryForList(
                        "SELECT table_name FROM information_schema.tables"
                                + " WHERE table_schema = 'public' AND table_type = 'BASE TABLE'",
                        String.class))
                .containsExactlyInAnyOrder(
                        "flyway_schema_history",
                        "users",
                        "email_verification_token",
                        "password_reset_token",
                        "refresh_token",
                        "board",
                        "board_member",
                        "board_invitation",
                        "board_column",
                        "task",
                        "subtask",
                        "comment",
                        "comment_mention",
                        "tag",
                        "task_tag",
                        "notification");
    }

    @Test
    void positionUniquesAreDeferred() {
        assertThat(jdbc.queryForList(
                        "SELECT conname FROM pg_constraint WHERE contype = 'u' AND condeferrable AND condeferred",
                        String.class))
                .containsExactlyInAnyOrder("uq_board_column_position", "uq_task_position", "uq_subtask_position");
    }

    @Test
    void swappingTwoColumnPositionsInOneTransactionSucceeds() {
        UUID board = insertBoard(insertUser());
        UUID first = insertColumn(board, 1000);
        UUID second = insertColumn(board, 2000);

        // El estado intermedio repite la posición 2000; la restricción diferida no se queja hasta el commit
        jdbc.update("UPDATE board_column SET position = 2000 WHERE id = ?", first);
        jdbc.update("UPDATE board_column SET position = 1000 WHERE id = ?", second);
        jdbc.execute("SET CONSTRAINTS ALL IMMEDIATE");

        assertThat(jdbc.queryForObject("SELECT position FROM board_column WHERE id = ?", Integer.class, first))
                .isEqualTo(2000);
    }

    @Test
    void duplicatedColumnPositionFailsAtCommitCheck() {
        UUID board = insertBoard(insertUser());
        insertColumn(board, 1000);
        UUID second = insertColumn(board, 2000);

        jdbc.update("UPDATE board_column SET position = 1000 WHERE id = ?", second);

        assertThatThrownBy(() -> jdbc.execute("SET CONSTRAINTS ALL IMMEDIATE"))
                .isInstanceOf(DataIntegrityViolationException.class)
                .hasMessageContaining("uq_board_column_position");
    }

    @Test
    void pendingAndCompletedTasksAreAccepted() {
        UUID board = insertBoard(insertUser());
        UUID column = insertColumn(board, 1000);

        insertTask(board, column, 1000, false, null);
        insertTask(board, null, null, true, NOW);

        assertThat(jdbc.queryForObject("SELECT count(*) FROM task WHERE board_id = ?", Integer.class, board))
                .isEqualTo(2);
    }

    @ParameterizedTest(name = "isDone={0}, columna={1}, posición={2}, completedAt={3}")
    @CsvSource({
        "true,  true,  false, true",
        "true,  false, true,  true",
        "true,  false, false, false",
        "false, false, true,  false",
        "false, true,  false, false"
    })
    void taskInconsistentWithDoneStateIsRejected(
            boolean isDone, boolean withColumn, boolean withPosition, boolean withCompletedAt) {
        UUID board = insertBoard(insertUser());
        UUID column = insertColumn(board, 1000);

        assertThatThrownBy(() -> insertTask(
                        board,
                        withColumn ? column : null,
                        withPosition ? 1000 : null,
                        isDone,
                        withCompletedAt ? NOW : null))
                .isInstanceOf(DataIntegrityViolationException.class)
                .hasMessageContaining("ck_task_done_state");
    }

    @Test
    void taskStartDateAfterDueDateIsRejected() {
        UUID board = insertBoard(insertUser());
        UUID column = insertColumn(board, 1000);

        assertThatThrownBy(() -> jdbc.update(
                        "INSERT INTO task (id, board_id, column_id, title, position, start_date, due_date, version,"
                                + " created_at, updated_at) VALUES (?, ?, ?, 'Tarea', 1000, ?, ?, 0, ?, ?)",
                        UUID.randomUUID(),
                        board,
                        column,
                        LocalDate.parse("2026-10-20"),
                        LocalDate.parse("2026-10-19"),
                        NOW,
                        NOW))
                .isInstanceOf(DataIntegrityViolationException.class)
                .hasMessageContaining("ck_task_dates");
    }

    @Test
    void columnTaskLimitDefaultsTo50() {
        UUID column = insertColumn(insertBoard(insertUser()), 1000);

        assertThat(jdbc.queryForObject("SELECT task_limit FROM board_column WHERE id = ?", Integer.class, column))
                .isEqualTo(50);
    }

    @ParameterizedTest
    @ValueSource(ints = {0, 101})
    void columnTaskLimitOutOfRangeIsRejected(int taskLimit) {
        UUID board = insertBoard(insertUser());

        assertThatThrownBy(() -> jdbc.update(
                        "INSERT INTO board_column (id, board_id, name, position, task_limit) VALUES (?, ?, 'Columna',"
                                + " 1000, ?)",
                        UUID.randomUUID(),
                        board,
                        taskLimit))
                .isInstanceOf(DataIntegrityViolationException.class)
                .hasMessageContaining("ck_board_column_task_limit");
    }

    @Test
    void secondOwnerOfABoardIsRejected() {
        UUID owner = insertUser();
        UUID board = insertBoard(owner);
        insertMember(board, owner, "OWNER");

        assertThatThrownBy(() -> insertMember(board, insertUser(), "OWNER"))
                .isInstanceOf(DataIntegrityViolationException.class)
                .hasMessageContaining("uq_board_member_owner");
    }

    @Test
    void secondPendingInvitationForTheSameUserIsRejected() {
        UUID owner = insertUser();
        UUID board = insertBoard(owner);
        UUID invited = insertUser();
        insertInvitation(board, invited, owner, "PENDING");

        assertThatThrownBy(() -> insertInvitation(board, invited, owner, "PENDING"))
                .isInstanceOf(DataIntegrityViolationException.class)
                .hasMessageContaining("uq_board_invitation_pending");
    }

    @Test
    void newPendingInvitationAfterARejectedOneIsAccepted() {
        UUID owner = insertUser();
        UUID board = insertBoard(owner);
        UUID invited = insertUser();
        insertInvitation(board, invited, owner, "REJECTED");

        insertInvitation(board, invited, owner, "PENDING");

        assertThat(jdbc.queryForObject(
                        "SELECT count(*) FROM board_invitation WHERE invited_user_id = ?", Integer.class, invited))
                .isEqualTo(2);
    }

    @Test
    void tagNameIsUniquePerBoardIgnoringCase() {
        UUID board = insertBoard(insertUser());
        insertTag(board, "Bug");

        assertThatThrownBy(() -> insertTag(board, "bug"))
                .isInstanceOf(DataIntegrityViolationException.class)
                .hasMessageContaining("uq_tag_board_name");
    }

    @Test
    void repeatedNotificationDedupeKeyIsRejected() {
        UUID user = insertUser();
        insertNotification(user, "2026-W43");

        assertThatThrownBy(() -> insertNotification(user, "2026-W43"))
                .isInstanceOf(DataIntegrityViolationException.class)
                .hasMessageContaining("uq_notification_dedupe");
    }

    private UUID insertUser() {
        UUID id = UUID.randomUUID();
        jdbc.update(
                "INSERT INTO users (id, name, email, account_provider, account_state, created_at, updated_at)"
                        + " VALUES (?, 'Usuario', ?, 'LOCAL', 'ACTIVE', ?, ?)",
                id,
                id + "@taskflow.test",
                NOW,
                NOW);
        return id;
    }

    private UUID insertBoard(UUID ownerId) {
        UUID id = UUID.randomUUID();
        jdbc.update(
                "INSERT INTO board (id, name, color, owner_id, version, created_at, updated_at, last_activity_at)"
                        + " VALUES (?, 'Tablero', '#4A3FD6', ?, 0, ?, ?, ?)",
                id,
                ownerId,
                NOW,
                NOW,
                NOW);
        return id;
    }

    private void insertMember(UUID boardId, UUID userId, String role) {
        jdbc.update(
                "INSERT INTO board_member (id, board_id, user_id, role, joined_at) VALUES (?, ?, ?, ?, ?)",
                UUID.randomUUID(),
                boardId,
                userId,
                role,
                NOW);
    }

    private void insertInvitation(UUID boardId, UUID invitedUserId, UUID invitedByUserId, String status) {
        jdbc.update(
                "INSERT INTO board_invitation (id, board_id, invited_user_id, invited_by_user_id, status, expires_at,"
                        + " created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                UUID.randomUUID(),
                boardId,
                invitedUserId,
                invitedByUserId,
                status,
                NOW.plusDays(5),
                NOW);
    }

    private UUID insertColumn(UUID boardId, int position) {
        UUID id = UUID.randomUUID();
        jdbc.update(
                "INSERT INTO board_column (id, board_id, name, position) VALUES (?, ?, 'Columna', ?)",
                id,
                boardId,
                position);
        return id;
    }

    private void insertTask(UUID boardId, UUID columnId, Integer position, boolean isDone, OffsetDateTime completedAt) {
        jdbc.update(
                "INSERT INTO task (id, board_id, column_id, title, is_done, completed_at, position, version,"
                        + " created_at, updated_at) VALUES (?, ?, ?, 'Tarea', ?, ?, ?, 0, ?, ?)",
                UUID.randomUUID(),
                boardId,
                columnId,
                isDone,
                completedAt,
                position,
                NOW,
                NOW);
    }

    private void insertTag(UUID boardId, String name) {
        jdbc.update(
                "INSERT INTO tag (id, board_id, name, color) VALUES (?, ?, ?, '#3B30B0')",
                UUID.randomUUID(),
                boardId,
                name);
    }

    private void insertNotification(UUID userId, String dedupeKey) {
        jdbc.update(
                "INSERT INTO notification (id, user_id, type, payload, dedupe_key, created_at)"
                        + " VALUES (?, ?, 'WEEKLY_DIGEST', '{}'::jsonb, ?, ?)",
                UUID.randomUUID(),
                userId,
                dedupeKey,
                NOW);
    }
}

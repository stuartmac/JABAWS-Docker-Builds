package jabaws.docker;

import java.io.File;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.List;
import java.util.Timer;
import java.util.TimerTask;

import javax.servlet.ServletContext;
import javax.servlet.ServletContextEvent;
import javax.servlet.ServletContextListener;

/**
 * Nightly online backup of the JABAWS execution-statistics database.
 *
 * <p>Why this class exists, and why it lives inside the webapp
 * <p>-------------------------------------------------------
 * JABAWS keeps its statistics in an <em>embedded</em> Apache Derby database
 * ({@code webapps/jabaws/ExecutionStatistic}), which means the Tomcat JVM holds
 * an exclusive lock on it for as long as the container runs. Nothing outside
 * that JVM -- not {@code ij}, not {@code docker exec}, not a sidecar -- can open
 * the database to dump it, and copying the directory underneath a live writer
 * can capture a torn, unrecoverable snapshot. The only backup that does not
 * require stopping the container is one taken from inside the JVM that already
 * has the database open, which is what this listener is.
 *
 * <p>It calls Derby's own {@code SYSCS_UTIL.SYSCS_BACKUP_DATABASE}, which
 * quiesces the database, checkpoints it and copies it out, so the result is a
 * consistent, directly restorable database rather than a hopeful file copy.
 * Alongside it we export {@code exec_stat} to CSV: the Derby backup is what you
 * restore, the CSV is what stays readable when no compatible Derby is at hand.
 *
 * <p>Scheduling happens here, in-process, for the same reason log rotation does
 * (see log4j.properties): it keeps the image free of a cron daemon, a sidecar,
 * and any host-side setup.
 *
 * <p>Configuration (environment variables, all optional)
 * <p>--------------------------------------------------
 * <ul>
 * <li>{@code JABAWS_STATS_BACKUP} -- {@code 0} disables the schedule entirely.
 * <li>{@code JABAWS_STATS_BACKUP_DIR} -- destination root. Default
 *     {@code /usr/local/tomcat/stats-backups}.
 * <li>{@code JABAWS_STATS_BACKUP_AT} -- {@code HH:MM}, container-local time.
 *     Default {@code 03:15}.
 * <li>{@code JABAWS_STATS_BACKUP_KEEP} -- how many nightly snapshots to keep.
 *     Default {@code 7}. Older ones are pruned after each successful run.
 * </ul>
 *
 * <p>Progress and errors go to {@code ServletContext.log}, which Tomcat writes
 * to {@code logs/localhost.<date>.log} in the logs volume -- not to
 * {@code docker logs}.
 */
public final class StatsBackup implements ServletContextListener {

	/** Same URL StatDB uses, so we join the already-booted database rather than trying to boot a second one. */
	private static final String DB_URL = "jdbc:derby:ExecutionStatistic;create=false";
	private static final String DRIVER = "org.apache.derby.jdbc.EmbeddedDriver";
	private static final String DEFAULT_DIR = "/usr/local/tomcat/stats-backups";
	private static final LocalTime DEFAULT_AT = LocalTime.of(3, 15);
	private static final int DEFAULT_KEEP = 7;

	/** Snapshot directory names, and the only names the pruner will ever delete. */
	private static final DateTimeFormatter STAMP = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss");
	private static final String STAMP_PATTERN = "\\d{8}-\\d{6}";

	private ServletContext context;
	private Timer timer;
	private File backupRoot;
	private LocalTime runAt;
	private int keep;

	@Override
	public void contextInitialized(ServletContextEvent event) {
		context = event.getServletContext();

		if ("0".equals(System.getenv("JABAWS_STATS_BACKUP"))) {
			context.log("[stats-backup] disabled via JABAWS_STATS_BACKUP=0");
			return;
		}

		String dir = System.getenv("JABAWS_STATS_BACKUP_DIR");
		backupRoot = new File(dir == null || dir.trim().isEmpty() ? DEFAULT_DIR : dir.trim());
		runAt = parseTime(System.getenv("JABAWS_STATS_BACKUP_AT"));
		keep = parseKeep(System.getenv("JABAWS_STATS_BACKUP_KEEP"));

		if (!backupRoot.isDirectory() && !backupRoot.mkdirs()) {
			context.log("[stats-backup] cannot create " + backupRoot + " -- nightly backup disabled");
			return;
		}
		if (!backupRoot.canWrite()) {
			context.log("[stats-backup] " + backupRoot + " is not writable -- nightly backup disabled");
			return;
		}

		// Derby resolves a relative database name against derby.system.home. StatDB
		// sets it to the webapp root when it first connects; if we get here first,
		// set the same value ourselves. The property is read once, when the engine
		// boots, so whichever of us runs first decides -- and both point at the same
		// directory, so there is only ever one booted copy of the database.
		if (System.getProperty("derby.system.home") == null) {
			String root = context.getRealPath("/");
			if (root != null) {
				System.setProperty("derby.system.home", root);
			}
		}

		timer = new Timer("jabaws-stats-backup", true);
		schedule();
	}

	@Override
	public void contextDestroyed(ServletContextEvent event) {
		if (timer != null) {
			timer.cancel();
		}
	}

	/**
	 * Queues the next run. Each run reschedules itself rather than using a fixed
	 * 24h period, so the backup stays at the configured wall-clock time across a
	 * daylight-saving change instead of drifting by an hour.
	 */
	private void schedule() {
		LocalDateTime next = LocalDateTime.now().with(runAt);
		if (!next.isAfter(LocalDateTime.now())) {
			next = next.plusDays(1);
		}
		Date when = Date.from(next.atZone(ZoneId.systemDefault()).toInstant());

		timer.schedule(new TimerTask() {
			@Override
			public void run() {
				try {
					backup();
				} catch (Throwable t) {
					// Never let a failed run kill the schedule -- tomorrow's may well work.
					context.log("[stats-backup] backup failed", t);
				} finally {
					schedule();
				}
			}
		}, when);

		context.log("[stats-backup] next run " + next + " -> " + backupRoot
				+ " (keeping " + keep + ")");
	}

	private void backup() throws SQLException {
		long started = System.currentTimeMillis();
		File target = new File(backupRoot, STAMP.format(LocalDateTime.now()));

		Connection conn = connect();
		try {
			// Waits for in-flight transactions, then checkpoints and copies. Derby
			// writes the database into <target>/ExecutionStatistic, creating <target>.
			CallableStatement backup = conn.prepareCall("CALL SYSCS_UTIL.SYSCS_BACKUP_DATABASE(?)");
			try {
				backup.setString(1, target.getAbsolutePath());
				backup.execute();
			} finally {
				backup.close();
			}

			// Nulls take Derby's defaults: comma-separated, double-quoted, platform
			// codeset. The file must not already exist, which a fresh timestamped
			// directory guarantees.
			CallableStatement export = conn.prepareCall(
					"CALL SYSCS_UTIL.SYSCS_EXPORT_QUERY(?, ?, ?, ?, ?)");
			try {
				export.setString(1, "select * from exec_stat");
				export.setString(2, new File(target, "exec_stat.csv").getAbsolutePath());
				export.setNull(3, java.sql.Types.CHAR);
				export.setNull(4, java.sql.Types.CHAR);
				export.setNull(5, java.sql.Types.VARCHAR);
				export.execute();
			} finally {
				export.close();
			}
		} finally {
			// Closes our handle only; the database stays booted for JABAWS itself.
			try {
				conn.close();
			} catch (SQLException ignored) {
				// Nothing useful to do -- the backup itself already succeeded or threw.
			}
		}

		context.log("[stats-backup] wrote " + target + " (" + (size(target) / 1024) + " KB) in "
				+ (System.currentTimeMillis() - started) + " ms");
		prune();
	}

	private Connection connect() throws SQLException {
		try {
			Class.forName(DRIVER);
		} catch (ClassNotFoundException e) {
			throw new SQLException("Derby embedded driver not on the webapp classpath", e);
		}
		return DriverManager.getConnection(DB_URL);
	}

	/** Deletes all but the newest {@code keep} snapshots. Timestamped names sort chronologically. */
	private void prune() {
		String[] snapshots = backupRoot.list();
		if (snapshots == null) {
			return;
		}
		List<String> ours = new ArrayList<String>();
		for (String name : snapshots) {
			// Only ever delete directories this class created: the backup root may
			// be a mount that holds other things.
			if (name.matches(STAMP_PATTERN) && new File(backupRoot, name).isDirectory()) {
				ours.add(name);
			}
		}
		Collections.sort(ours, Collections.reverseOrder());
		for (String name : ours.subList(Math.min(keep, ours.size()), ours.size())) {
			File stale = new File(backupRoot, name);
			if (delete(stale)) {
				context.log("[stats-backup] pruned " + stale);
			} else {
				context.log("[stats-backup] could not prune " + stale);
			}
		}
	}

	private static boolean delete(File file) {
		File[] children = file.listFiles();
		if (children != null) {
			for (File child : children) {
				if (!delete(child)) {
					return false;
				}
			}
		}
		return file.delete();
	}

	private static long size(File file) {
		File[] children = file.listFiles();
		if (children == null) {
			return file.length();
		}
		long total = 0;
		for (File child : children) {
			total += size(child);
		}
		return total;
	}

	private LocalTime parseTime(String value) {
		if (value == null || value.trim().isEmpty()) {
			return DEFAULT_AT;
		}
		try {
			return LocalTime.parse(value.trim(), DateTimeFormatter.ofPattern("H:mm"));
		} catch (RuntimeException e) {
			context.log("[stats-backup] JABAWS_STATS_BACKUP_AT='" + value
					+ "' is not HH:MM -- using " + DEFAULT_AT);
			return DEFAULT_AT;
		}
	}

	private int parseKeep(String value) {
		if (value == null || value.trim().isEmpty()) {
			return DEFAULT_KEEP;
		}
		try {
			int parsed = Integer.parseInt(value.trim());
			if (parsed < 1) {
				throw new NumberFormatException(value);
			}
			return parsed;
		} catch (NumberFormatException e) {
			context.log("[stats-backup] JABAWS_STATS_BACKUP_KEEP='" + value
					+ "' is not a positive integer -- using " + DEFAULT_KEEP);
			return DEFAULT_KEEP;
		}
	}
}

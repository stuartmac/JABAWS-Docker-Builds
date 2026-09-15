package jabaws.docker;

import java.io.File;
import java.util.Date;
import java.util.Timer;
import java.util.TimerTask;

import javax.servlet.ServletContext;
import javax.servlet.ServletContextEvent;
import javax.servlet.ServletContextListener;

/**
 * Removes "phantom" job directories: directories under {@code jobsout} that
 * were created for a submission that never actually received its input.
 *
 * <p>Why this exists
 * <p>-----------------
 * JABAWS creates a job's work directory ({@code Configurator.setupWorkDirectory})
 * before it writes {@code input.txt} and before the job is registered with the
 * engine ({@code WSUtil.align}/{@code analize} write the input file, then call
 * {@code submitJob} -- in that order). If anything throws in between -- a
 * sequence-limit check, an I/O error writing the input file, an aborted
 * request -- the directory is left behind, never registered, and therefore
 * never reaches any terminal status. Nothing upstream ever cleans these up
 * from that: {@code DirCleaner} eventually would, once the directory's mtime
 * crosses {@code local.jobdir.maxlifespan} hours (see the Dockerfile's
 * {@code jobdir.*} patch), but in the meantime the built-in per-minute
 * statistics sweep ({@code local.stat.collector.update.frequency}, default 1)
 * re-visits every such directory on every run and logs a
 * {@code FileNotFoundException} trying to read its (nonexistent) input file --
 * one warning per phantom directory, every sweep, forever.
 *
 * <p>A directory missing {@code input.txt} can only be one of these phantoms:
 * every real job has {@code input.txt} written, synchronously, in the same
 * request that creates the directory, before the job is ever registered or
 * runnable -- so there is no window in a legitimate job's life where the
 * directory exists but the input file does not. This listener deletes any
 * {@code jobsout} directory that is both missing {@code input.txt} and older
 * than a grace period, well ahead of the normal retention sweep.
 *
 * <p>Configuration (environment variables, all optional)
 * <p>--------------------------------------------------
 * <ul>
 * <li>{@code JABAWS_PHANTOM_CLEANER} -- {@code 0} disables the schedule
 *     entirely.
 * <li>{@code JABAWS_PHANTOM_CLEANER_GRACE_MINUTES} -- how old a directory
 *     must be before it is considered abandoned rather than mid-submission.
 *     Default {@code 30}.
 * <li>{@code JABAWS_PHANTOM_CLEANER_INTERVAL_MINUTES} -- how often the sweep
 *     runs. Default {@code 10}.
 * </ul>
 *
 * <p>Progress and errors go to {@code ServletContext.log}, which Tomcat writes
 * to {@code logs/localhost.<date>.log} in the logs volume -- not to
 * {@code docker logs}.
 */
public final class PhantomJobCleaner implements ServletContextListener {

	private static final String INPUT_FILE = "input.txt";
	private static final int DEFAULT_GRACE_MINUTES = 30;
	private static final int DEFAULT_INTERVAL_MINUTES = 10;

	private ServletContext context;
	private Timer timer;
	private File jobsOut;
	private long graceMillis;

	@Override
	public void contextInitialized(ServletContextEvent event) {
		context = event.getServletContext();

		if ("0".equals(System.getenv("JABAWS_PHANTOM_CLEANER"))) {
			context.log("[phantom-cleaner] disabled via JABAWS_PHANTOM_CLEANER=0");
			return;
		}

		String realPath = context.getRealPath("jobsout");
		if (realPath == null) {
			context.log("[phantom-cleaner] cannot resolve jobsout -- disabled");
			return;
		}
		jobsOut = new File(realPath);
		if (!jobsOut.isDirectory()) {
			context.log("[phantom-cleaner] " + jobsOut + " does not exist -- disabled");
			return;
		}

		int graceMinutes = parsePositiveInt(System.getenv("JABAWS_PHANTOM_CLEANER_GRACE_MINUTES"),
				DEFAULT_GRACE_MINUTES, "JABAWS_PHANTOM_CLEANER_GRACE_MINUTES");
		int intervalMinutes = parsePositiveInt(System.getenv("JABAWS_PHANTOM_CLEANER_INTERVAL_MINUTES"),
				DEFAULT_INTERVAL_MINUTES, "JABAWS_PHANTOM_CLEANER_INTERVAL_MINUTES");
		graceMillis = graceMinutes * 60L * 1000L;

		context.log("[phantom-cleaner] watching " + jobsOut + " every " + intervalMinutes
				+ " min, grace period " + graceMinutes + " min");

		timer = new Timer("jabaws-phantom-cleaner", true);
		long periodMillis = intervalMinutes * 60L * 1000L;
		timer.schedule(new TimerTask() {
			@Override
			public void run() {
				try {
					sweep();
				} catch (Throwable t) {
					// Never let a failed sweep kill the schedule -- the next one may well work.
					context.log("[phantom-cleaner] sweep failed", t);
				}
			}
		}, periodMillis, periodMillis);
	}

	@Override
	public void contextDestroyed(ServletContextEvent event) {
		if (timer != null) {
			timer.cancel();
		}
	}

	private void sweep() {
		File[] dirs = jobsOut.listFiles();
		if (dirs == null) {
			return;
		}
		long now = System.currentTimeMillis();
		int removed = 0;
		for (File dir : dirs) {
			if (!dir.isDirectory() || dir.getName().startsWith(".")) {
				continue;
			}
			if (new File(dir, INPUT_FILE).exists()) {
				continue;
			}
			if (now - dir.lastModified() < graceMillis) {
				continue;
			}
			if (delete(dir)) {
				context.log("[phantom-cleaner] removed orphaned job directory " + dir.getName()
						+ " (never received " + INPUT_FILE + ")");
				removed++;
			} else {
				context.log("[phantom-cleaner] could not remove " + dir.getName());
			}
		}
		if (removed > 0) {
			context.log("[phantom-cleaner] sweep at " + new Date() + " removed " + removed + " directories");
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

	private int parsePositiveInt(String value, int fallback, String name) {
		if (value == null || value.trim().isEmpty()) {
			return fallback;
		}
		try {
			int parsed = Integer.parseInt(value.trim());
			if (parsed < 1) {
				throw new NumberFormatException(value);
			}
			return parsed;
		} catch (NumberFormatException e) {
			context.log("[phantom-cleaner] " + name + "='" + value + "' is not a positive integer -- using "
					+ fallback);
			return fallback;
		}
	}
}

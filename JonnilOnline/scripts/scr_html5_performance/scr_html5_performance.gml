/* Rendering-mode identifiers are shared by saved settings and the UI: Auto chooses from diagnostics,
Full keeps normal rendering, and Reduced enables the lighter rendering path */
#macro JONNIL_HTML5_PERFORMANCE_AUTO 0
#macro JONNIL_HTML5_PERFORMANCE_FULL 1
#macro JONNIL_HTML5_PERFORMANCE_REDUCED 2

/// @description Own HTML5 diagnostics, frame samples, saved rendering mode and startup guidance state
function scr_html5_performance() constructor
{
	/* settings_file selects the shared client INI, and settings_section isolates browser performance preferences */
	settings_file = "client_settings.ini";
	settings_section = "html5_performance";

	/* Increment when revised guidance should be shown again for the same browser */
	guidance_version = 2;

	/* Only a browser runtime outside GX uses this controller's diagnostics and adaptive mode */
	is_html5 = os_browser != browser_not_a_browser && os_type != os_gxgames;

	/* sample_capacity limits the rolling history to 600 accepted frame times
	frame_samples_ms is a zero-filled millisecond ring, sample_count tracks filled entries,
	and sample_write_index is the next zero-based position to replace */
	sample_capacity = 600;
	frame_samples_ms = array_create(sample_capacity, 0);
	sample_count = 0;
	sample_write_index = 0;

	/* The first statistics check is due after 1000 current_time milliseconds
	resume_skip_frames excludes 12 startup Steps in HTML5 and none natively
	last_page_active starts true to detect the first visibility or focus transition */
	statistics_due_at = current_time + 1000;
	resume_skip_frames = is_html5 ? 12 : 0;
	last_page_active = true;

	/* The percentile and worst-frame values start at -1 for not measured
	The three long-frame counters start at zero and count samples above their stated millisecond thresholds */
	frame_p50_ms = -1;
	frame_p95_ms = -1;
	frame_p99_ms = -1;
	frame_worst_ms = -1;
	frames_over_20_ms = 0;
	frames_over_33_ms = 0;
	frames_over_50_ms = 0;

	/* poor_window_streak and healthy_window_streak count consecutive qualifying statistics checks
	auto_reduced_for_pacing starts false until sustained poor results enable reduction */
	poor_window_streak = 0;
	healthy_window_streak = 0;
	auto_reduced_for_pacing = false;

	/* browser_name/family identify the browser, browser_version starts unknown,
	and platform_name identifies its operating platform, with native labels outside HTML5
	mobile_browser starts false until browser diagnostics classify the device */
	browser_name = is_html5 ? "Unknown" : "Native application";
	browser_family = is_html5 ? "unknown" : "native";
	browser_version = "";
	platform_name = is_html5 ? "Unknown" : "Native";
	mobile_browser = false;

	/* renderer_name/vendor hold exposed graphics details, with pending or inapplicable defaults
	renderer_class starts unknown and renderer_detail_available starts false until the bridge supplies evidence */
	renderer_name = is_html5 ? "Not available yet" : "Not applicable";
	renderer_vendor = is_html5 ? "Not available yet" : "Not applicable";
	renderer_class = "unknown";
	renderer_detail_available = false;

	/* device_pixel_ratio defaults to one CSS-to-device-pixel scaling
	hardware_concurrency and device_memory_gb start at -1 for unavailable approximate hardware values */
	device_pixel_ratio = 1;
	hardware_concurrency = -1;
	device_memory_gb = -1;

	/* Page visibility and focus start true until queried
	Native diagnostics are already ready, browser diagnostics wait for the first probe, and diagnostics_error starts empty
	The probe count starts zero, and next_diagnostic_probe_at zero makes the first update eligible immediately */
	page_visible = true;
	page_focused = true;
	diagnostics_ready = !is_html5;
	diagnostics_error = "";
	diagnostic_probe_count = 0;
	next_diagnostic_probe_at = 0;

	/* applied_mode starts Auto, mode mirrors it for callers, and draft_mode is the editable selection
	active_reduced starts false until refresh_active_mode evaluates the active choice */
	applied_mode = JONNIL_HTML5_PERFORMANCE_AUTO;
	mode = applied_mode;
	draft_mode = applied_mode;
	active_reduced = false;

	/* The saved seen signature and current guidance signature start empty
	guidance_pending waits for a ready unseen signature, and guidance_shown_this_session prevents repeat display in this runtime */
	guidance_seen_signature = "";
	guidance_signature = "";
	guidance_pending = false;
	guidance_shown_this_session = false;

	/* Start with no visible clipboard feedback and no synchronous copy-request error */
	copy_feedback_cleared = true;
	copy_request_error = "";

	#region /* Rendering Mode and Saved Settings */
	/// @description Check numeric bounds before mode rounding
	/// @param {Real} value Candidate mode
	/// @returns {Bool} Whether it is within Auto through Reduced
	mode_is_valid = function(value)
	{
		/* Require a numeric value within the three mode identifiers before callers round and apply it */
		return is_real(value)
			&& value >= JONNIL_HTML5_PERFORMANCE_AUTO
			&& value <= JONNIL_HTML5_PERFORMANCE_REDUCED;
	}

	/// @description Name the rounded mode, defaulting other identifiers to Auto
	/// @param {Real} value Mode identifier. Defaults to applied_mode
	/// @returns {String} Auto, Full or Reduced
	mode_name = function(value = applied_mode)
	{
		/* Rounded Full and Reduced identifiers use their explicit labels, while all other values label as Auto */
		switch (round(value))
		{
			case JONNIL_HTML5_PERFORMANCE_FULL: return "Full";
			case JONNIL_HTML5_PERFORMANCE_REDUCED: return "Reduced";
			default: return "Auto";
		}
	}

	/// @description Get the selected mode's display name
	/// @param {Real} value Mode identifier. Defaults to applied_mode
	/// @returns {String} Mode label
	mode_label = function(value = applied_mode)
	{
		return mode_name(value);
	}

	/// @description Name the current rendering path
	/// @returns {String} Full or Reduced
	effective_mode_label = function()
	{
		/* The effective label describes actual reduction rather than the saved Auto/Full/Reduced preference */
		return active_reduced ? "Reduced" : "Full";
	}

	/// @description Load HTML5 mode and guidance markers from the client INI, retaining current values on failure
	load_settings = function()
	{
		/* Native builds leave the authored browser defaults untouched instead of reading browser-only settings */
		if (!is_html5)
		{
			return;
		}

		try
		{
			ini_open(settings_file);

			/* Read and round the saved mode, using Auto when no setting exists */
			var saved_mode = round(ini_read_real(settings_section, "mode", JONNIL_HTML5_PERFORMANCE_AUTO));

			/* Only a supported saved identifier replaces the applied, public and draft modes */
			if (mode_is_valid(saved_mode))
			{
				applied_mode = saved_mode;
				mode = saved_mode;
				draft_mode = saved_mode;
			}
			guidance_seen_signature = ini_read_string(settings_section, "guidance_signature", "");
			ini_close();
		}

		/* Keep the current in-memory settings on an INI failure and attempt to close any open INI */
		catch(e)
		{
			try { ini_close(); } catch(close_error) {}
		}
	}

	/// @description Persist the applied HTML5 mode and seen guidance signature
	/// @returns {Bool} Whether HTML5 settings were written successfully
	save_settings = function()
	{
		/* Native builds do not persist browser performance settings */
		if (!is_html5)
		{
			return false;
		}

		try
		{
			ini_open(settings_file);
			ini_write_real(settings_section, "mode", applied_mode);
			ini_write_string(settings_section, "guidance_signature", guidance_seen_signature);
			ini_close();
			return true;
		}

		/* A settings-write exception attempts INI cleanup and reports false */
		catch(e)
		{
			try { ini_close(); } catch(close_error) {}
			return false;
		}
	}

	/// @description Change the draft selection after validating bounds
	/// @param {Real} value Candidate mode
	/// @returns {Bool} Whether the value was accepted
	stage_mode = function(value)
	{
		/* Reject unsupported values before changing the draft selection */
		if (!mode_is_valid(value))
		{
			return false;
		}

		draft_mode = round(value);
		return true;
	}

	/// @description Cycle the draft through its three choices
	/// @param {Real} direction Negative cycles backward, other values forward
	/// @returns {Real} New draft identifier
	cycle_draft_mode = function(direction)
	{
		/* Negative direction cycles backward, while zero or positive direction cycles forward
		Adding three before modulo wraps either direction through the three mode identifiers */
		var change = direction < 0 ? -1 : 1;
		draft_mode = (draft_mode + change + 3) mod 3;
		return draft_mode;
	}

	/// @description Restore the draft from the applied selection
	/// @returns {Real} Restored draft mode
	cancel_draft_mode = function()
	{
		draft_mode = applied_mode;
		return draft_mode;
	}

	/// @description Apply the staged mode and persist it. A save failure does not undo the applied mode
	/// @returns {Bool} Whether an HTML5 mode was accepted and its settings saved
	apply_draft_mode = function()
	{
		/* Only supported HTML5 draft values may become active and be saved */
		if (!is_html5 || !mode_is_valid(draft_mode))
		{
			return false;
		}

		applied_mode = round(draft_mode);
		mode = applied_mode;
		refresh_active_mode();
		return save_settings();
	}

	/// @description Apply a supported HTML5 mode and optionally save it
	/// @param {Real} value Candidate mode
	/// @param {Bool} persist Save settings after applying. Defaults to true
	/// @returns {Bool} Whether accepted and any requested save succeeded. Save failure keeps the applied change
	set_mode = function(value, persist = true)
	{
		/* Reject native builds and unsupported mode values without changing any selection */
		if (!is_html5 || !mode_is_valid(value))
		{
			return false;
		}

		applied_mode = round(value);
		mode = applied_mode;
		draft_mode = applied_mode;
		refresh_active_mode();

		/* A nonpersistent change succeeds immediately, while a persistent change reports the settings-save result */
		return !persist || save_settings();
	}

	/// @description Describe the highest-priority Auto reduction reason
	/// @returns {String} Mode, WebGL, renderer or sustained-pacing explanation
	auto_reason = function()
	{
		/* Explain that Auto reasoning is unused outside HTML5 or when another mode is applied */
		if (!is_html5 || applied_mode != JONNIL_HTML5_PERFORMANCE_AUTO)
		{
			return "Not using Auto mode";
		}

		/* Unavailable WebGL takes priority in the displayed reduction reason */
		if (!webgl_enabled)
		{
			return "WebGL is unavailable";
		}

		/* Software rendering is the next reduction reason when WebGL exists */
		if (renderer_class == "software")
		{
			return "Software renderer detected";
		}

		/* A sustained pacing reduction is reported after the renderer-specific reasons */
		if (auto_reduced_for_pacing)
		{
			return "Sustained slow or uneven frame pacing";
		}
		return "No reduction currently needed";
	}

	/// @description Resolve the effective rendering path and publish its global flag
	/// @returns {Bool} Whether Reduced rendering is active
	refresh_active_mode = function()
	{
		/* Native builds always clear the browser reduction flag */
		if (!is_html5)
		{
			active_reduced = false;
		}

		/* Explicit Reduced forces the lighter rendering path regardless of diagnostics */
		else if (applied_mode == JONNIL_HTML5_PERFORMANCE_REDUCED)
		{
			active_reduced = true;
		}

		/* Explicit Full disables reduction even when diagnostics suggest it */
		else if (applied_mode == JONNIL_HTML5_PERFORMANCE_FULL)
		{
			active_reduced = false;
		}

		/* Auto reduces when WebGL is unavailable, a software renderer is detected, or sustained poor pacing was measured */
		else
		{
			active_reduced = !webgl_enabled
				|| renderer_class == "software"
				|| auto_reduced_for_pacing;
		}

		/* Publish the effective reduction state for drawing systems that read the shared global */
		global.html5_reduced_performance_mode = active_reduced;
		return active_reduced;
	}
	#endregion /* Rendering Mode and Saved Settings END */

	#region /* Browser Diagnostics and Guidance State */
	/// @description Rebuild the browser/versioned guidance signature and pending decision
	refresh_guidance_signature = function()
	{
		/* Native builds clear guidance state and do not create a browser-specific signature */
		if (!is_html5)
		{
			guidance_signature = "";
			guidance_pending = false;
			return;
		}

		guidance_signature = "v" + string(guidance_version)
			+ "|" + string(browser_name)
			+ "|webgl:" + string(webgl_enabled);

		/* Queue guidance only after its decision is ready, it has not appeared this session and the current signature differs from the saved one */
		guidance_pending = guidance_decision_ready()
			&& !guidance_shown_this_session
			&& guidance_signature != guidance_seen_signature;
	}

	/// @description Check whether enough diagnostic evidence or probe attempts exist
	/// @returns {Bool} Whether guidance may be evaluated
	guidance_decision_ready = function()
	{
		/* Native builds need no browser wait
		HTML5 needs ready diagnostics plus known renderer evidence, unavailable WebGL, or at least three attempts */
		return !is_html5
			|| (diagnostics_ready
				&& (!webgl_enabled || renderer_class != "unknown" || diagnostic_probe_count >= 3));
	}

	/// @description Check for an unseen ready browser signature
	/// @returns {Bool} Whether the current signature needs a session check
	guidance_check_required = function()
	{
		/* An initialized, nonempty unseen browser signature needs checking only until guidance is shown this session */
		return is_html5
			&& diagnostics_ready
			&& !guidance_shown_this_session
			&& guidance_signature != ""
			&& guidance_signature != guidance_seen_signature;
	}

	/// @description Check the ready pending session guidance decision
	/// @returns {Bool} Whether guidance should be displayed
	should_show_guidance = function()
	{
		/* Show only a ready, pending HTML5 guidance decision that has not already appeared in this session */
		return is_html5 && diagnostics_ready && guidance_pending && !guidance_shown_this_session;
	}

	/// @description Record the current signature and suppress repeat guidance this session
	/// @returns {Bool} Whether an HTML5 signature was saved. Save failure keeps its in-memory seen state
	mark_guidance_seen = function()
	{
		/* Without an HTML5 signature, there is no valid guidance marker to persist */
		if (!is_html5 || guidance_signature == "")
		{
			return false;
		}

		guidance_seen_signature = guidance_signature;
		guidance_pending = false;
		guidance_shown_this_session = true;
		return save_settings();
	}

	/// @description Refresh the browser bridge values, then reconsider guidance and the active rendering mode
	/// @returns {Bool} Whether the HTML5 diagnostic queries completed
	refresh_diagnostics = function()
	{
		/* Native builds mark diagnostics ready without calling browser-only bridge functions */
		if (!is_html5)
		{
			diagnostics_ready = true;
			return false;
		}

		diagnostic_probe_count++;
		diagnostics_error = "";
		try
		{
			/* Tell the bridge whether the runner uses WebGL, encoding the Boolean as numeric one or zero */
			html5_diag_refresh(webgl_enabled ? 1 : 0);
			browser_name = string(html5_diag_browser_name());
			browser_family = string_lower(string(html5_diag_browser_family()));
			browser_version = string(html5_diag_browser_version());
			platform_name = string(html5_diag_platform_name());
			mobile_browser = html5_diag_is_mobile() >= 1;
			renderer_name = string(html5_diag_renderer());
			renderer_vendor = string(html5_diag_vendor());
			renderer_class = string_lower(string(html5_diag_renderer_class()));
			renderer_detail_available = html5_diag_renderer_detail_available() >= 1;
			device_pixel_ratio = max(0.1, real(html5_diag_device_pixel_ratio()));
			hardware_concurrency = real(html5_diag_hardware_concurrency());
			device_memory_gb = real(html5_diag_device_memory_gb());
			page_visible = html5_diag_page_visible() >= 1;
			page_focused = html5_diag_page_focused() >= 1;

			/* Empty browser names use a readable Unknown label */
			if (browser_name == "") browser_name = "Unknown";

			/* Empty browser-family values retain the unknown classification */
			if (browser_family == "") browser_family = "unknown";

			/* Empty platform names use the Unknown fallback */
			if (platform_name == "") platform_name = "Unknown";

			/* Missing renderer details get an explicit browser-disclosure label */
			if (renderer_name == "") renderer_name = "Not exposed by browser";

			/* Missing vendor details use the same disclosure fallback */
			if (renderer_vendor == "") renderer_vendor = "Not exposed by browser";

			/* Only software and hardware classifications are accepted, with all other bridge values normalized to unknown */
			if (renderer_class != "software" && renderer_class != "hardware") renderer_class = "unknown";

			diagnostics_ready = true;
			refresh_guidance_signature();
			refresh_active_mode();
			return true;
		}

		/* A bridge exception retains its diagnostic and marks the probe finished so guidance can still be reconsidered */
		catch(e)
		{
			diagnostics_error = string(e.message);
			diagnostics_ready = true;
			refresh_guidance_signature();
			return false;
		}
	}
	#endregion /* Browser Diagnostics and Guidance State END */

	#region /* Frame Sampling and Auto Mode */
	/// @description Clear frame statistics and consecutive check streaks
	/// @param {Bool} reset_auto_state Also clear pacing-based reduction and refresh the effective mode
	clear_measurements_internal = function(reset_auto_state)
	{
		sample_count = 0;
		sample_write_index = 0;
		frame_p50_ms = -1;
		frame_p95_ms = -1;
		frame_p99_ms = -1;
		frame_worst_ms = -1;
		frames_over_20_ms = 0;
		frames_over_33_ms = 0;
		frames_over_50_ms = 0;
		statistics_due_at = current_time + 1000;
		poor_window_streak = 0;
		healthy_window_streak = 0;

		/* Clear the pacing-based reduction only when requested, preserving it across ordinary focus transitions */
		if (reset_auto_state)
		{
			auto_reduced_for_pacing = false;
			refresh_active_mode();
		}
	}

	/// @description Reset frame and optional composite timings, then skip the HTML5 startup warmup
	reset_measurements = function()
	{
		clear_measurements_internal(true);

		/* Skip 12 fresh HTML5 Steps after manual reset, with no native sampling delay */
		resume_skip_frames = is_html5 ? 12 : 0;

		/* Reset the optional last composite timing to -1 for not measured only when that global exists */
		if (variable_global_exists("drawing_composite_last_ms")) global.drawing_composite_last_ms = -1;

		/* Reset the optional average composite timing to -1 for not measured only when that global exists */
		if (variable_global_exists("drawing_composite_average_ms")) global.drawing_composite_average_ms = -1;

		/* Reset the optional peak composite timing to -1 for not measured only when that global exists */
		if (variable_global_exists("drawing_composite_peak_ms")) global.drawing_composite_peak_ms = -1;
	}

	/// @description Append an accepted duration to the bounded rolling ring
	/// @param {Real} milliseconds Frame duration already validated by update
	add_frame_sample = function(milliseconds)
	{
		/* Replace the next ring entry, wrap its index at capacity, and grow the filled count only until the ring is full */
		frame_samples_ms[sample_write_index] = milliseconds;
		sample_write_index = (sample_write_index + 1) mod sample_capacity;
		sample_count = min(sample_capacity, sample_count + 1);
	}

	/// @description Select a clamped nearest-rank percentile
	/// @param {Array<Real>} sorted_samples Ascending millisecond samples
	/// @param {Real} fraction Percentile fraction
	/// @returns {Real} Selected duration, or -1 for an empty array
	percentile_from_sorted = function(sorted_samples, fraction)
	{
		/* count is the number of ascending samples available for percentile selection */
		var count = array_length(sorted_samples);

		/* No samples yield -1 rather than indexing an empty array */
		if (count <= 0)
		{
			return -1;
		}

		/* Use the nearest-rank percentile's zero-based index, clamped to the available endpoints */
		var index = clamp(ceil(fraction * count) - 1, 0, count - 1);
		return sorted_samples[index];
	}

	/// @description Rebuild rolling percentiles and advance Auto pacing streaks
	calculate_statistics = function()
	{
		/* An empty ring cannot produce percentiles or a worst-frame value */
		if (sample_count <= 0)
		{
			return;
		}

		/* Copy the filled ring entries into a new array so sorting does not alter the next-write ring order */
		var sorted_samples = array_create(sample_count, 0);
		frames_over_20_ms = 0;
		frames_over_33_ms = 0;
		frames_over_50_ms = 0;

		/* Visit each filled zero-based ring entry to copy it and rebuild the long-frame counters */
		for (var i = 0; i < sample_count; i++)
		{
			/* value is this accepted frame's duration in milliseconds */
			var value = frame_samples_ms[i];
			sorted_samples[i] = value;

			/* Count frames strictly above 20 milliseconds */
			if (value > 20) frames_over_20_ms++;

			/* Count frames strictly above roughly 33.3 milliseconds independently of the lower threshold */
			if (value > 33.333) frames_over_33_ms++;

			/* Count frames strictly above 50 milliseconds, allowing one long frame to contribute to all three totals */
			if (value > 50) frames_over_50_ms++;
		}

		array_sort(sorted_samples, true);
		frame_p50_ms = percentile_from_sorted(sorted_samples, 0.50);
		frame_p95_ms = percentile_from_sorted(sorted_samples, 0.95);
		frame_p99_ms = percentile_from_sorted(sorted_samples, 0.99);
		frame_worst_ms = sorted_samples[sample_count - 1];

		/* Evaluate overlapping sample windows once a second after 180 accepted frames.
		Three poor checks enable pacing reduction in Auto. Ten healthy checks clear it */
		if (sample_count >= 180)
		{
			/* poor_window marks p95 above 20 ms or p99 above 33.333 ms
			healthy_window requires both p95 at most 18 ms and p99 at most 25 ms, leaving a neutral range between them */
			var poor_window = frame_p95_ms > 20 || frame_p99_ms > 33.333;
			var healthy_window = frame_p95_ms <= 18 && frame_p99_ms <= 25;

			/* A poor check advances its streak and breaks the healthy streak */
			if (poor_window)
			{
				poor_window_streak++;
				healthy_window_streak = 0;

				/* Three consecutive poor checks enable the pacing reduction */
				if (poor_window_streak >= 3)
				{
					auto_reduced_for_pacing = true;
				}
			}

			/* A healthy check advances its streak and breaks the poor streak */
			else if (healthy_window)
			{
				healthy_window_streak++;
				poor_window_streak = 0;

				/* Ten consecutive healthy checks clear the pacing reduction, requiring longer recovery than degradation */
				if (healthy_window_streak >= 10)
				{
					auto_reduced_for_pacing = false;
				}
			}

			/* Neutral checks break both consecutive streaks without changing the current reduction state */
			else
			{
				poor_window_streak = 0;
				healthy_window_streak = 0;
			}

			refresh_active_mode();
		}
	}

	/// @description Refresh optional browser visibility and focus hints
	/// @returns {Bool} Whether visible and focused. Query exceptions assume activity
	update_page_state = function()
	{
		/* Native builds are treated as active without querying browser visibility */
		if (!is_html5)
		{
			return true;
		}

		try
		{
			page_visible = html5_diag_page_visible() >= 1;
			page_focused = html5_diag_page_focused() >= 1;
		}
		catch(e)
		{
			/* Continue measuring if a browser declines these optional page-state queries */
			page_visible = true;
			page_focused = true;
		}

		/* Only a visible and focused browser page contributes normal frame samples */
		return page_visible && page_focused;
	}

	/// @description Sample delta_time once per controller Step while the HTML5 page is visible and focused
	update = function()
	{
		/* Native updates clear the browser reduction global and skip all browser diagnostics and sampling */
		if (!is_html5)
		{
			global.html5_reduced_performance_mode = false;
			return;
		}

		/* Probe renderer information when its current_time millisecond deadline is reached */
		if (current_time >= next_diagnostic_probe_at)
		{
			refresh_diagnostics();

			/* Retry an unknown renderer every 500 ms for the first six probes, otherwise wait 30 seconds */
			var retry_quickly = renderer_class == "unknown" && diagnostic_probe_count < 6;
			next_diagnostic_probe_at = current_time + (retry_quickly ? 500 : 30000);
		}

		/* Combine the current visibility and focus queries before deciding whether this Step can be measured */
		var page_active = update_page_state();

		/* Inactive pages skip samples and prepare a 12-Step warmup for their eventual return */
		if (!page_active)
		{
			/* Clear measurements once when leaving an active page, preserving the current pacing reduction */
			if (last_page_active)
			{
				clear_measurements_internal(false);
			}
			last_page_active = false;
			resume_skip_frames = 12;
			return;
		}

		/* On return to activity, clear old timing windows and restart the 12-Step warmup */
		if (!last_page_active)
		{
			last_page_active = true;
			clear_measurements_internal(false);
			resume_skip_frames = 12;
		}

		/* Consume one warmup Step without recording delta_time */
		if (resume_skip_frames > 0)
		{
			resume_skip_frames--;
			return;
		}

		/* Convert GameMaker delta_time from microseconds to the millisecond sampling unit */
		var frame_ms = real(delta_time) / 1000;

		/* Reject nonpositive times and gaps above 250 ms, skipping two more Steps after such a gap */
		if (frame_ms <= 0 || frame_ms > 250)
		{
			/* Long suspend/resume gaps are not representative gameplay frames */
			resume_skip_frames = 2;
			return;
		}

		add_frame_sample(frame_ms);

		/* Recalculate statistics at most once per second, scheduling the next check from current_time */
		if (current_time >= statistics_due_at)
		{
			calculate_statistics();
			statistics_due_at = current_time + 1000;
		}
	}
	#endregion /* Frame Sampling and Auto Mode END */

	#region /* Performance Guidance Text */
	/// @description Describe renderer evidence without claiming direct acceleration-setting access
	/// @returns {String} Renderer summary
	renderer_summary = function()
	{
		/* Native builds use an inapplicable renderer explanation */
		if (!is_html5) return "Renderer diagnostics are not used by this build.";

		/* Unavailable WebGL overrides any cached renderer classification in the summary */
		if (!webgl_enabled) return "WebGL is unavailable";

		/* Software and hardware evidence receive their respective summaries, while unknown values report uncertainty */
		switch (renderer_class)
		{
			case "software": return "Software renderer detected";
			case "hardware": return "Hardware acceleration appears active";
			default: return "Hardware acceleration could not be determined";
		}
	}

	/// @description Check ready browser evidence for missing WebGL or software rendering
	/// @returns {Bool} Whether acceleration guidance is relevant
	acceleration_warning_active = function()
	{
		/* Warn only after HTML5 diagnostics are ready and either WebGL is absent or the renderer is classified as software */
		return is_html5
			&& diagnostics_ready
			&& (!webgl_enabled || renderer_class == "software");
	}

	/// @description Select the warning label from WebGL availability
	/// @returns {String} Guidance-link text
	acceleration_warning_label = function()
	{
		/* Absent WebGL uses its specific guidance label, otherwise the warning describes inferred inactive acceleration */
		if (!webgl_enabled)
		{
			return "WebGL is unavailable - View performance guidance";
		}
		return "Hardware acceleration appears inactive - View guidance";
	}

	/// @description Describe sample readiness and recent or sustained pacing
	/// @returns {String} Frame-pacing summary
	performance_summary = function()
	{
		/* Native builds use an inapplicable performance-controls summary */
		if (!is_html5) return "HTML5 performance controls are not used by this build.";

		/* Fewer than 180 accepted frames still report measurement in progress */
		if (sample_count < 180) return "Measuring browser frame pacing...";

		/* An active sustained-pacing decision takes priority over a single recent-window warning */
		if (auto_reduced_for_pacing) return "Sustained slow or uneven frame pacing was detected.";

		/* Recent poor percentiles get a warning even before the three-check reduction streak completes */
		if (frame_p95_ms > 20 || frame_p99_ms > 33.333) return "Recent frame pacing is slow or uneven.";
		return "Recent frame pacing looks stable.";
	}

	/// @description Build authored renderer and platform/browser guidance
	/// @returns {Array<String>} Ordered guidance lines
	get_guidance_lines = function()
	{
		/* Accumulate the renderer explanation and platform/browser instructions in ordered text lines */
		var lines = [];
		lines[array_length(lines)] = "HTML5 performance guidance";
		lines[array_length(lines)] = "The game can inspect renderer clues, but browsers do not expose their acceleration setting itself.";

		/* Explain absent WebGL directly before considering renderer details */
		if (!webgl_enabled)
		{
			lines[array_length(lines)] = "WebGL did not start, so the game cannot use its normal accelerated renderer.";
		}

		/* With WebGL available, describe the renderer classification evidence */
		else
		{
			/* Software, hardware and unknown classifications produce distinct guidance, keeping hardware acceleration as an inference */
			switch (renderer_class)
			{
				case "software":
					lines[array_length(lines)] = "A software renderer appears to be active, which can cause low or uneven frame rates.";
					break;
				case "hardware":
					lines[array_length(lines)] = "The renderer appears hardware-accelerated. This is an inference from renderer information.";
					break;
				default:
					lines[array_length(lines)] = "The browser hid detailed renderer information, so acceleration status is unknown.";
					break;
			}
		}

		lines[array_length(lines)] = "";

		/* Mobile browser guidance takes priority because its acceleration controls differ from desktop settings */
		if (mobile_browser)
		{
			lines[array_length(lines)] = browser_name + " on " + platform_name;
			lines[array_length(lines)] = "Mobile browsers normally manage graphics acceleration themselves and do not provide the desktop acceleration toggle.";
			lines[array_length(lines)] = "Install current browser and system updates, close graphics-heavy tabs, and test with Battery Saver or Low Power Mode off.";
		}

		/* ChromeOS uses system-managed acceleration advice before browser-specific desktop instructions */
		else if (platform_name == "ChromeOS")
		{
			lines[array_length(lines)] = browser_name + " on ChromeOS";
			lines[array_length(lines)] = "ChromeOS normally manages graphics acceleration. Install current ChromeOS updates and restart the Chromebook.";
			lines[array_length(lines)] = "If play stutters, connect power and temporarily turn Energy Saver off while testing.";
		}

		/* Chrome receives its authored browser-specific guidance after mobile and ChromeOS cases have been excluded */
		else if (browser_name == "Google Chrome")
		{
			lines[array_length(lines)] = "Google Chrome";
			lines[array_length(lines)] = "1. Open Chrome Settings > System.";
			lines[array_length(lines)] = "2. Turn ON \"Use graphics acceleration when available\".";
			lines[array_length(lines)] = "3. Select Relaunch, then reopen Jonnil Online.";
			lines[array_length(lines)] = "4. If play still stutters on battery, open Settings > Performance and temporarily turn Energy Saver off.";
			lines[array_length(lines)] = "Memory Saver normally does not need to be disabled while Jonnil Online is the visible tab.";
			lines[array_length(lines)] = "If acceleration was already on, update Chrome, the operating system, and the graphics driver; Chrome may have disabled it for compatibility.";
		}

		/* Edge receives its authored browser-specific guidance after mobile and ChromeOS cases have been excluded */
		else if (browser_name == "Microsoft Edge")
		{
			lines[array_length(lines)] = "Microsoft Edge";
			lines[array_length(lines)] = "1. Open Edge Settings > System and performance > System.";
			lines[array_length(lines)] = "2. Turn ON \"Use graphics acceleration when available\".";
			lines[array_length(lines)] = "3. Select Restart, then reopen Jonnil Online.";
			lines[array_length(lines)] = "If play stutters on battery, open Settings > System and performance > Performance and temporarily turn \"Enable energy saver\" off.";
		}

		/* Firefox receives its authored browser-specific guidance after mobile and ChromeOS cases have been excluded */
		else if (browser_name == "Mozilla Firefox")
		{
			lines[array_length(lines)] = "Mozilla Firefox";
			lines[array_length(lines)] = "1. Open Firefox Settings > General > Performance.";
			lines[array_length(lines)] = "2. Clear \"Use recommended performance settings\".";
			lines[array_length(lines)] = "3. Turn ON \"Use hardware acceleration when available\", then restart Firefox.";
		}

		/* Safari receives its authored browser-specific guidance after mobile and ChromeOS cases have been excluded */
		else if (browser_name == "Safari")
		{
			lines[array_length(lines)] = "Safari";
			lines[array_length(lines)] = "Safari manages graphics acceleration automatically and does not provide a normal toggle.";
			lines[array_length(lines)] = "Install current Safari/macOS updates, close graphics-heavy tabs, and test with Low Power Mode off if play stutters.";
		}

		/* Opera receives its authored browser-specific guidance after mobile and ChromeOS cases have been excluded */
		else if (browser_name == "Opera")
		{
			lines[array_length(lines)] = "Opera";
			lines[array_length(lines)] = "Open Settings > Advanced > System, turn ON \"Use graphics acceleration when available\", then relaunch Opera.";
		}

		/* Brave receives its authored browser-specific guidance after mobile and ChromeOS cases have been excluded */
		else if (browser_name == "Brave")
		{
			lines[array_length(lines)] = "Brave";
			lines[array_length(lines)] = "Open Settings > System, turn ON \"Use graphics acceleration when available\", then relaunch Brave.";
		}

		/* Vivaldi receives its authored browser-specific guidance after mobile and ChromeOS cases have been excluded */
		else if (browser_name == "Vivaldi")
		{
			lines[array_length(lines)] = "Vivaldi";
			lines[array_length(lines)] = "Open Settings > Performance, turn ON \"Use Hardware Acceleration When Available\", then restart Vivaldi.";
			lines[array_length(lines)] = "If play stutters on battery, temporarily set Energy Saver to \"Never Save Energy\" while testing.";
		}

		/* Unrecognized browsers use general guidance, substituting 'Your browser' for the Unknown label */
		else
		{
			lines[array_length(lines)] = browser_name == "Unknown" ? "Your browser" : browser_name;
			lines[array_length(lines)] = "If the browser provides a System or Performance graphics-acceleration setting, enable it and then fully restart the browser.";
		}

		lines[array_length(lines)] = "";
		lines[array_length(lines)] = "Keep the game tab visible, close unusually heavy tabs, and connect the device to power when testing performance.";
		return lines;
	}

	/// @description Join guidance lines while preserving spacer lines
	/// @returns {String} LF-separated guidance
	get_guidance_text = function()
	{
		/* lines is the ordered guidance array and result begins empty for its LF-joined text */
		var lines = get_guidance_lines();
		var result = "";

		/* Join every zero-based guidance line, including intentional empty spacer lines */
		for (var i = 0; i < array_length(lines); i++)
		{
			/* Add LF before every line after the first so empty spacer entries remain represented */
			if (i > 0) result += "\n";
			result += lines[i];
		}
		return result;
	}

	/// @description Expose the guidance-line builder
	/// @returns {Array<String>} Ordered guidance lines
	guidance_lines = function()
	{
		return get_guidance_lines();
	}

	/// @description Expose the guidance text builder
	/// @returns {String} LF-separated guidance
	guidance_text = function()
	{
		return get_guidance_text();
	}
	#endregion /* Performance Guidance Text END */

	#region /* Diagnostic Reports and Clipboard Feedback */
	/// @description Format measured durations or their negative sentinel
	/// @param {Real} value Duration in milliseconds
	/// @returns {String} Two-decimal ms text or not measured
	format_ms = function(value)
	{
		/* Negative timing sentinels display as not measured, while measured values show two decimal places and ms */
		return value < 0 ? "not measured" : string_format(value, 1, 2) + " ms";
	}

	/// @description Format exposed numeric data or an unavailable sentinel
	/// @param {Real} value Numeric data, or negative/nonnumeric when unavailable
	/// @param {String} suffix Unit suffix. Defaults to empty text
	/// @returns {String} Formatted value or not exposed
	format_optional_number = function(value, suffix = "")
	{
		/* Nonnumeric or negative hardware/display sentinels show not exposed, otherwise append the optional unit suffix */
		return !is_real(value) || value < 0 ? "not exposed" : string(value) + suffix;
	}

	/// @description Capture a local wall-clock diagnostic timestamp
	/// @returns {String} YYYY-MM-DD HH:MM:SS
	report_timestamp = function()
	{
		/* Capture the local wall-clock datetime once for the report's generated-at timestamp */
		var now = date_current_datetime();
		return string(date_get_year(now)) + "-"
			+ string_replace_all(string_format(date_get_month(now), 2, 0), " ", "0") + "-"
			+ string_replace_all(string_format(date_get_day(now), 2, 0), " ", "0") + " "
			+ string_replace_all(string_format(date_get_hour(now), 2, 0), " ", "0") + ":"
			+ string_replace_all(string_format(date_get_minute(now), 2, 0), " ", "0") + ":"
			+ string_replace_all(string_format(date_get_second(now), 2, 0), " ", "0");
	}

	/// @description Build local browser, renderer, display and timing diagnostics
	/// @returns {String} LF-separated report. Does not send it automatically
	make_diagnostics_report = function()
	{
		/* Build ordered report lines from runtime, browser, renderer, approximate hardware and measured frame state */
		var lines = [];
		lines[array_length(lines)] = "Jonnil Online HTML5 performance report";
		lines[array_length(lines)] = "Generated: " + report_timestamp();
		lines[array_length(lines)] = "Privacy: no username or persistent ID is included. This report does include browser, renderer, approximate hardware, and display details.";
		lines[array_length(lines)] = "The game does not send this report automatically; it is copied only when requested.";
		lines[array_length(lines)] = "";

		/* Runtime labels distinguish HTML5 from native, browser version is appended only when known,
		mobile status adds its platform suffix, and WebGL labels reflect the active renderer flag */
		lines[array_length(lines)] = "Runtime: " + (is_html5 ? "HTML5" : "Native");
		lines[array_length(lines)] = "Game version: " + string(GM_version);
		lines[array_length(lines)] = "GameMaker runtime: " + string(GM_runtime_version);
		lines[array_length(lines)] = "Build date: " + scr_get_build_date(true, true);
		lines[array_length(lines)] = "Browser: " + browser_name + (browser_version == "" ? "" : " " + browser_version);
		lines[array_length(lines)] = "Browser family: " + browser_family;
		lines[array_length(lines)] = "Platform: " + platform_name + (mobile_browser ? " (mobile/tablet browser)" : "");
		lines[array_length(lines)] = "WebGL: " + (webgl_enabled ? "enabled" : "disabled");
		lines[array_length(lines)] = "Renderer: " + renderer_name;
		lines[array_length(lines)] = "Renderer vendor: " + renderer_vendor;
		lines[array_length(lines)] = "Renderer classification: " + renderer_class;
		lines[array_length(lines)] = "Unmasked renderer detail available: " + string(renderer_detail_available);
		lines[array_length(lines)] = "Device pixel ratio: " + string_format(device_pixel_ratio, 1, 2);
		lines[array_length(lines)] = "Approximate logical processors: " + format_optional_number(hardware_concurrency);
		lines[array_length(lines)] = "Approximate device memory: " + format_optional_number(device_memory_gb, " GB");
		lines[array_length(lines)] = "Page visible/focused: " + string(page_visible) + "/" + string(page_focused);
		lines[array_length(lines)] = "";

		/* Window and display dimensions begin at -1 for unavailable values before optional runtime queries */
		var window_width = -1;
		var window_height = -1;
		var display_width = -1;
		var display_height = -1;
		try
		{
			window_width = window_get_width();
			window_height = window_get_height();
			display_width = display_get_width();
			display_height = display_get_height();
		}

		/* Ignore optional dimension-query failures and retain unavailable sentinels for any values not obtained */
		catch(e) {}

		lines[array_length(lines)] = "Game window: " + format_optional_number(window_width) + " x " + format_optional_number(window_height);
		lines[array_length(lines)] = "Reported display: " + format_optional_number(display_width) + " x " + format_optional_number(display_height);
		lines[array_length(lines)] = "GUI: " + string(display_get_gui_width()) + " x " + string(display_get_gui_height());

		/* Read application-surface dimensions only while that surface exists */
		if (surface_exists(application_surface))
		{
			lines[array_length(lines)] = "Application surface: " + string(surface_get_width(application_surface)) + " x " + string(surface_get_height(application_surface));
		}

		lines[array_length(lines)] = "";
		lines[array_length(lines)] = "Frame samples: " + string(sample_count) + "/" + string(sample_capacity);
		lines[array_length(lines)] = "Frame time p50/p95/p99/worst: "
			+ format_ms(frame_p50_ms) + " / " + format_ms(frame_p95_ms) + " / "
			+ format_ms(frame_p99_ms) + " / " + format_ms(frame_worst_ms);
		lines[array_length(lines)] = "Long frames >20/>33.3/>50 ms: "
			+ string(frames_over_20_ms) + "/" + string(frames_over_33_ms) + "/" + string(frames_over_50_ms);
		lines[array_length(lines)] = "Browser cadence hint (fps_real): " + string_format(fps_real, 1, 1);
		lines[array_length(lines)] = "Selected performance mode: " + mode_name(applied_mode);

		/* Report the effective Full or Reduced rendering path separately from the selected preference */
		lines[array_length(lines)] = "Active rendering mode: " + (active_reduced ? "Reduced" : "Full");
		lines[array_length(lines)] = "Auto decision: " + auto_reason();

		/* Include the composite-timing section when at least one optional timing global has been initialized */
		if (variable_global_exists("drawing_composite_last_ms")
		|| variable_global_exists("drawing_composite_average_ms")
		|| variable_global_exists("drawing_composite_peak_ms"))
		{
			lines[array_length(lines)] = "";
			lines[array_length(lines)] = "Drawing composite timings:";

			/* Read the optional last timing only after checking its global exists */
			if (variable_global_exists("drawing_composite_last_ms"))
				lines[array_length(lines)] = "  Last: " + format_ms(global.drawing_composite_last_ms);

			/* Read the optional average timing only after checking its global exists */
			if (variable_global_exists("drawing_composite_average_ms"))
				lines[array_length(lines)] = "  Average: " + format_ms(global.drawing_composite_average_ms);

			/* Read the optional peak timing only after checking its global exists */
			if (variable_global_exists("drawing_composite_peak_ms"))
				lines[array_length(lines)] = "  Peak: " + format_ms(global.drawing_composite_peak_ms);
		}

		/* Append a bridge-error section only when a diagnostic was retained */
		if (diagnostics_error != "")
		{
			lines[array_length(lines)] = "";
			lines[array_length(lines)] = "Browser diagnostics error: " + diagnostics_error;
		}

		/* Start the joined report empty */
		var report = "";

		/* Join every zero-based report line, preserving intentional blank entries */
		for (var i = 0; i < array_length(lines); i++)
		{
			/* Insert LF only before lines after the first */
			if (i > 0) report += "\n";
			report += lines[i];
		}
		return report;
	}

	/// @description Expose the diagnostic report builder
	/// @returns {String} Local diagnostic report
	diagnostic_report = function()
	{
		return make_diagnostics_report();
	}

	/// @description Request a browser clipboard copy. Poll clipboard_status for completion
	/// @returns {Bool} Whether the browser bridge accepted the request
	copy_diagnostics_report = function()
	{
		copy_feedback_cleared = false;
		copy_request_error = "";

		/* Native builds report that this clipboard bridge is unavailable instead of calling JavaScript */
		if (!is_html5)
		{
			copy_request_error = "Clipboard diagnostics are only available in the HTML5 build.";
			return false;
		}

		try
		{
			/* A numeric result of at least one means the asynchronous browser copy request was accepted, with completion polled separately */
			return html5_diag_copy_text(make_diagnostics_report()) >= 1;
		}

		/* Retain a synchronous bridge exception and report that the request was not accepted */
		catch(e)
		{
			copy_request_error = string(e.message);
			return false;
		}
	}

	/// @description Expose the browser report-copy request
	/// @returns {Bool} Whether the asynchronous request was accepted
	copy_report = function()
	{
		return copy_diagnostics_report();
	}

	/// @description Read the latest report-copy state
	/// @returns {Real} 0 idle, 1 pending, 2 success or -1 failure
	clipboard_status = function()
	{
		/* Cleared feedback reports idle status zero without polling the bridge */
		if (copy_feedback_cleared) return 0;

		/* An unsupported runtime or retained request error reports failure status -1 */
		if (!is_html5 || copy_request_error != "") return -1;

		/* Poll the bridge's numeric status, treating a thrown query as failure */
		try { return round(html5_diag_copy_status()); } catch(e) { return -1; }
	}

	/// @description Read the retained request or bridge clipboard diagnostic
	/// @returns {String} Failure text
	clipboard_error = function()
	{
		/* A synchronous request error takes priority over later bridge diagnostics */
		if (copy_request_error != "") return copy_request_error;

		/* Native builds return the unavailable-bridge explanation */
		if (!is_html5) return "Clipboard diagnostics are only available in the HTML5 build.";

		/* Read the browser's asynchronous copy error, using the query exception message if polling throws */
		try { return string(html5_diag_copy_error()); } catch(e) { return string(e.message); }
	}

	/// @description Describe pending, successful or failed report copying
	/// @returns {String} Feedback, or empty text while idle
	clipboard_status_text = function()
	{
		/* Status 1 reports pending, 2 reports success, -1 reports failure, and all other values hide feedback */
		switch (clipboard_status())
		{
			case 1: return "Copying report...";
			case 2:
				try
				{
					/* Use the bridge's successful copy method when provided, otherwise return a plain success message */
					var clipboard_method_name = string(html5_diag_copy_method());
					return clipboard_method_name == "" ? "Report copied." : "Report copied using " + clipboard_method_name + ".";
				}

				/* A failed method-name query still reports copy success because status two already confirmed it */
				catch(e) { return "Report copied."; }
			case -1: return "Could not copy report: " + clipboard_error();
			default: return "";
		}
	}

	/// @description Expose the report-copy feedback text
	/// @returns {String} Clipboard status message
	copy_status_text = function()
	{
		return clipboard_status_text();
	}

	/// @description Hide report-copy feedback and clear the synchronous request error
	clear_copy_feedback = function()
	{
		copy_feedback_cleared = true;
		copy_request_error = "";
	}
	#endregion /* Diagnostic Reports and Clipboard Feedback END */

	load_settings();
	refresh_active_mode();
}

/// @description Get the shared browser diagnostics and performance controller
/// @returns {Struct} Lazily constructed scr_html5_performance instance
function scr_get_html5_performance()
{
	/* Construct one shared browser-performance controller for sampling, options, guidance and reports */
	static performance = new scr_html5_performance();
	return performance;
}

/// @description Format the release stamp or GameMaker build date for version labels
/// @param {Bool} include_hour Include the build hour, defaulting to false
/// @param {Bool} include_minute Include the build minute, defaulting to false. Both true flags select the public YYYY.M.1DDHHMM format
/// @returns {String} Version text. Without either flag, release stamps retain packed DDHHMMSS
function scr_get_build_date(include_hour = false, include_minute = false)
{
	/* Automatic releases pack GM_version as YYYY.M.DDHH.(MMSS+1).
	Keep separate calendar components so every output format uses the same time.
	GM_build_date supplies year, month, day, hour, minute and second until a valid
	release stamp replaces all six with its decoded release time */
	var year, month, day, hour, minute, second;
	year = date_get_year(GM_build_date);
	month = date_get_month(GM_build_date);
	day = date_get_day(GM_build_date);
	hour = date_get_hour(GM_build_date);
	minute = date_get_minute(GM_build_date);
	second = date_get_second(GM_build_date);

	/* Track whether version decoding produced a usable release timestamp.
	Start false so ordinary builds retain the GM_build_date fallback */
	var has_release_stamp = false;

	/* Split the dotted release version into its four encoded components.
	Other version shapes keep the fallback rather than entering this decoder */
	var version_parts = string_split(string(GM_version), ".");

	/* Decode only the four-part release format so each indexed component exists.
	Versions with another number of parts keep the build-date components */
	if (array_length(version_parts) == 4)
	{
		/* Read the candidate year and month, then unpack DDHH and MMSS into their
		calendar fields. The last version component was stored one above its packed
		value, so subtract one before separating its minute and second */
		var stamped_year = real(version_parts[0]);
		var stamped_month = real(version_parts[1]);
		var packed_day_hour = real(version_parts[2]);
		var packed_minute_second = real(version_parts[3]) - 1;
		var stamped_day = floor(packed_day_hour / 100);
		var stamped_hour = packed_day_hour mod 100;
		var stamped_minute = floor(packed_minute_second / 100);
		var stamped_second = packed_minute_second mod 100;

		/* Accept only the supported year floor and ordinary calendar/time ranges
		before replacing the build-date fallback. These bounds check day 1 through
		31 without checking whether that particular month actually has that day */
		if (stamped_year >= 2000)
		&& (stamped_month >= 1) && (stamped_month <= 12)
		&& (packed_day_hour >= 100)
		&& (stamped_day >= 1) && (stamped_day <= 31)
		&& (stamped_hour >= 0) && (stamped_hour <= 23)
		&& (packed_minute_second >= 0)
		&& (stamped_minute >= 0) && (stamped_minute <= 59)
		&& (stamped_second >= 0) && (stamped_second <= 59)
		{
			year = stamped_year;
			month = stamped_month;
			day = stamped_day;
			hour = stamped_hour;
			minute = stamped_minute;
			second = stamped_second;
			has_release_stamp = true;
		}
	}

	/* With both time flags off, return the short version label.
	A decoded release retains its packed time in the patch component,
	while an ordinary build uses just the calendar day */
	if (include_hour <= false)
	&& (include_minute <= false)
	{
		/* Use DDHHMMSS for a decoded release so its short label still distinguishes
		release times. Without a release stamp, fall through to the day-only label */
		if (has_release_stamp)
		{
			/* Pack the selected day, hour, minute and second into one numeric patch.
			The decimal place widths keep those fields distinct without extra dots */
			var release_patch = day * 1000000 + hour * 10000 + minute * 100 + second;
			return (string(year) + "." + string(month) + "." + string(release_patch));
		}
		return (string(year) + "." + string(month) + "." + string(day));
	}

	/* When both time flags are enabled, use the public three-component label.
	Its patch contains 1DDHHMM so the time fields stay fixed-width and the
	leading 1 keeps the patch from beginning with a zero */
	if (include_hour >= true)
	&& (include_minute >= true)
	{
		/* Build the six-digit DDHHMM text and turn format padding into zeros.
		Add the leading 1 to produce the shared SemVer-safe, fixed-width 1DDHHMM patch */
		var public_patch = string_replace_all(string_format(day * 10000 + hour * 100 + minute, 6, 0), " ", "0");
		return (string(year) + "." + string(month) + ".1" + public_patch);
	}

	/* If only minutes are requested, append the calendar day and minute as
	separate components. The hour is deliberately omitted in this format */
	else
	if (include_hour <= false)
	&& (include_minute >= true)
	{
		return (string(year) + "." + string(month) + "." + string(day) + "." + string(minute));
	}

	/* If only the hour is requested, append it after the calendar day.
	The minute is omitted because its flag is off */
	else
	if (include_hour >= true)
	&& (include_minute <= false)
	{
		return (string(year) + "." + string(month) + "." + string(day) + "." + string(hour));
	}
}

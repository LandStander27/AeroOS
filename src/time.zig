const std = @import("std");

const bs = @import("boot_services.zig");

pub fn sleepms(ms: u64) !void {
	const boot_services = try bs.init();
	const res = boot_services.stall(ms * 1000);
	if (res != .Success) {
		try res.err();
	}
}

pub const Time = struct {
	_time: std.os.uefi.Time,
	year: u16,
	month: u8,
	day: u8,
	hour: u8,
	minute: u8,
	second: u8,
	timezone: i16,

	fn days_in_year(year: u16, max_month: u32) u64 {
		const leap_year: std.time.epoch.YearLeapKind = if (std.time.epoch.isLeapYear(year)) .leap else .not_leap;
		var days: u64 = 0;
		var month: u64 = 0;
		while (month < max_month) : (month += 1) {
			days += std.time.epoch.getDaysInMonth(leap_year, @enumFromInt(month + 1));
		}
		return days;
	}

	pub fn unix(self: *const Time) u64 {
		var year: u16 = 0;
		var days: u64 = 0;

		while (year < (self._time.year - 1971)) : (year += 1) {
			days += days_in_year(year + 1970, 12);
		}

		days += days_in_year(self._time.year, @as(u4, @intCast(self._time.month)) - 1) + self._time.day;
		const hours = self._time.hour + (days * 24);
		const minutes = self._time.minute + (hours * 60);
		const seconds = self._time.second + (minutes * std.time.s_per_min);
		return seconds;
	}

	pub fn timezone_now() !Time {
		var t: std.os.uefi.Time = undefined;

		if (std.os.uefi.system_table.runtime_services.getTime(&t, null) != .Success) {
			return error.CouldNotGetTime;
		}

		return Time{
			._time = t,
			.year = t.year,
			.month = t.month,
			.day = t.day,
			.hour = t.hour,
			.minute = t.minute,
			.second = t.second,
			.timezone = @divFloor(t.timezone, 60),
		};
	}

	pub fn now() !Time {
		var t: std.os.uefi.Time = undefined;

		if (std.os.uefi.system_table.runtime_services.getTime(&t, null) != .Success) {
			return error.CouldNotGetTime;
		}

		var hour: i16 = @intCast(t.hour);

		hour += @divFloor(t.timezone, 60);
		if (hour < 0) {
			hour += 24;
		} else if (hour >= 24) {
			hour -= 24;
		}

		return Time{
			._time = t,
			.year = t.year,
			.month = t.month,
			.day = t.day,
			.hour = @intCast(hour),
			.minute = t.minute,
			.second = t.second,
			.timezone = @divFloor(t.timezone, 60),
		};
	}

};

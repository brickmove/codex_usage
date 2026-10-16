import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[2] / "scripts/release-policy.py"
spec = importlib.util.spec_from_file_location("release_policy", path)
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


def release(date, tag="v0.5.0", draft=False, prerelease=False):
    return dict(published_at=date, tag_name=tag, draft=draft, prerelease=prerelease)


class ReleasePolicyTests(unittest.TestCase):
    def check(self, releases, now):
        return policy.evaluate(releases, policy.parse_time(now))

    def test_first_release(self):
        self.assertTrue(self.check([], "2026-10-16T00:00:00Z")["eligible"])

    def test_same_day_fix_is_blocked(self):
        result = self.check([release("2026-10-16T02:52:00Z")], "2026-10-16T12:00:00Z")
        self.assertFalse(result["eligible"])
        self.assertEqual(result["earliestReleaseAt"], "2026-11-16T02:52:00Z")

    def test_boundary_to_the_second(self):
        releases = [release("2026-10-16T02:52:00Z")]
        self.assertFalse(self.check(releases, "2026-11-16T02:51:59Z")["eligible"])
        self.assertTrue(self.check(releases, "2026-11-16T02:52:00Z")["eligible"])

    def test_month_is_not_fixed_thirty_days(self):
        self.assertFalse(self.check([release("2026-10-16T00:00:00Z")], "2026-11-15T00:00:00Z")["eligible"])

    def test_month_end_and_leap_year(self):
        for start, end in [("2026-01-31", "2026-02-28"), ("2024-01-31", "2024-02-29"), ("2026-12-31", "2027-01-31")]:
            self.assertEqual(self.check([release(start + "T12:00:00Z")], start + "T12:00:00Z")["earliestReleaseAt"], end + "T12:00:00Z")

    def test_latest_publication_wins_across_unordered_pages(self):
        result = self.check([[release("2026-10-16T00:00:00Z", "v0.5.0")], [release("2026-10-01T00:00:00Z", "v9.0.0")]], "2026-11-02T00:00:00Z")
        self.assertFalse(result["eligible"])
        self.assertEqual(result["lastRelease"], "v0.5.0")

    def test_draft_does_not_count_but_prerelease_does(self):
        self.assertTrue(self.check([release(None, draft=True)], "2026-10-16T00:00:00Z")["eligible"])
        self.assertFalse(self.check([release("2026-10-15T00:00:00Z", prerelease=True)], "2026-10-16T00:00:00Z")["eligible"])

    def test_bad_api_responses_fail_closed(self):
        for data in [{"message": "API rate limit exceeded"}, [release(None)], [{"draft": "false"}], [release("2026-10-16")], [None]]:
            with self.assertRaises(ValueError):
                self.check(data, "2026-10-16T00:00:00Z")

    def test_timezone_offsets_refer_to_the_same_instant(self):
        self.assertTrue(self.check([release("2026-10-16T10:52:00+08:00")], "2026-11-16T02:52:00Z")["eligible"])


if __name__ == "__main__":
    unittest.main()

import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("exporter", Path(__file__).with_name("export-clockify.py"))
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


class ExportTests(unittest.TestCase):
    def workspace(self):
        return {"id": "workspace", "projects": [{"id": "p", "name": "Convex General", "clientId": "c", "color": "#ff8800"}], "clients": [{"id": "c", "name": "Convex"}], "tags": [{"id": "t", "name": "Video"}], "entries": [{"id": "e", "projectId": "p", "description": "Work", "tagIds": ["t"], "timeInterval": {"start": "2026-10-04T15:30:00Z", "end": "2026-10-04T16:30:00Z"}}]}

    def testNormalizationKeepsExactTimesAndSourceLabels(self):
        archive = exporter.normalize([self.workspace()])
        self.assertEqual(archive["categories"][0]["name"], "Convex")
        entry = archive["entries"][0]
        self.assertEqual(entry["clientId"], "clockify:workspace:e")
        self.assertEqual(entry["endedAt"] - entry["startedAt"], 3600000)
        self.assertEqual(entry["note"], "Work\nProject: Convex General · Tags: Video")
        self.assertEqual(archive, exporter.normalize([self.workspace()]))

    def testRunningTimersAreSkippedAndDuplicatesRejected(self):
        workspace = self.workspace()
        workspace["entries"][0]["timeInterval"]["end"] = None
        archive = exporter.normalize([workspace])
        self.assertEqual(archive["entries"], [])
        self.assertEqual(archive["skippedRunning"], 1)
        workspace = self.workspace()
        workspace["entries"] *= 2
        with self.assertRaises(RuntimeError):
            exporter.normalize([workspace])

    def testPaginationContinuesAfterShortPageWhenHeaderSaysNotLast(self):
        api = exporter.Clockify("test")
        calls = []
        def get(path, params):
            calls.append(params["page"])
            return ([{"id": str(params["page"])}], {"Last-Page": "true" if params["page"] == 3 else "false"})
        api.get = get
        records, audit = api.pages("test")
        self.assertEqual(calls, [1, 2, 3])
        self.assertEqual(len(records), 3)
        self.assertEqual(audit[-1]["lastPage"], "true")

    def testRepeatedPageFailsInsteadOfClaimingCompleteHistory(self):
        api = exporter.Clockify("test")
        api.get = lambda *args: ([{"id": "repeat"}], {})
        with self.assertRaises(RuntimeError):
            api.pages("test")


if __name__ == "__main__":
    unittest.main()

"""SP launch checks with fake processes; no app is opened or closed."""

import io
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import Mock, patch

from forge_tasks_world import sp_cdp as focus


class FocusLifecycleTests(unittest.TestCase):
    def test_missing_dependency_does_not_touch_app(self):
        spec = importlib.util.spec_from_file_location(
            'focus_script', Path(__file__).resolve().parents[1] / 'scripts/forge-sp-focus-project.py')
        script = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(script)
        with patch.dict('sys.modules', {'websocket': None}), \
             patch.object(script, 'ensure_cdp') as launch, \
             patch.object(script, 'write_focus_request') as write:
            with self.assertRaises(SystemExit):
                script.main(['focus', 'project'])
            launch.assert_not_called()
            write.assert_not_called()

    def test_ready_session_is_reused(self):
        with patch.object(focus, 'cdp_up', return_value=True), \
             patch.object(focus.subprocess, 'run') as run, \
             patch.object(focus.subprocess, 'Popen') as launch, \
             patch.object(focus.urllib.request, 'urlopen', return_value=io.BytesIO(
                 b'[{"type":"page","webSocketDebuggerUrl":"ws://127.0.0.1:9222/page"}]')):
            self.assertEqual(focus.ensure_cdp(), 'ws://127.0.0.1:9222/page')
            run.assert_not_called()
            launch.assert_not_called()

    def test_graceful_exit_precedes_launch(self):
        with patch.object(focus, 'cdp_up', return_value=False), \
             patch.object(focus, '_running', side_effect=[True, False]), \
             patch.object(focus.subprocess, 'run') as quit_app, \
             patch.object(focus.subprocess, 'Popen') as launch, \
             patch.object(focus.urllib.request, 'urlopen', return_value=io.BytesIO(
                 b'[{"type":"page","webSocketDebuggerUrl":"ws://127.0.0.1:9222/page"}]')):
            focus.ensure_cdp()
            quit_app.assert_called_once()
            launch.assert_called_once()
            self.assertNotIn('--remote-allow-origins=*', launch.call_args.args[0])

    def test_unresponsive_app_is_not_killed_or_relaunched(self):
        with patch.object(focus, 'cdp_up', return_value=False), \
             patch.object(focus.subprocess, 'run', return_value=Mock(returncode=0)) as run, \
             patch.object(focus.subprocess, 'Popen') as launch, \
             patch.object(focus.time, 'sleep'):
            with self.assertRaises(SystemExit):
                focus.ensure_cdp(timeout=0)
            launch.assert_not_called()
            self.assertFalse(any('pkill' in call.args[0] for call in run.call_args_list))

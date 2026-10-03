import { spawn } from 'node:child_process';

// Some macOS Chrome builds keep their background process alive after dumping
// the DOM. Wait for the complete document, then retire only our test process.
export async function dumpDOM(browser, args) {
  const child = spawn(browser, args, { stdio: ['ignore', 'pipe', 'pipe'] });
  let stdout = '';
  let stderr = '';
  let timer;
  const exited = new Promise(resolve => child.once('exit', resolve));
  try {
    return await new Promise((resolve, reject) => {
      timer = setTimeout(() => reject(new Error(`Browser layout check timed out: ${stderr}`)), 20000);
      child.once('error', reject);
      child.stdout.on('data', chunk => {
        stdout += chunk;
        if (stdout.length > 2 * 1024 * 1024) reject(new Error('Browser output exceeded limit'));
        else if (stdout.includes('</html>')) resolve(stdout);
      });
      child.stderr.on('data', chunk => { stderr = (stderr + chunk).slice(-2000); });
      child.once('exit', code => {
        if (!stdout.includes('</html>')) reject(new Error(`Browser exited ${code}: ${stderr}`));
      });
    });
  } finally {
    clearTimeout(timer);
    if (child.pid && child.exitCode === null && child.signalCode === null) {
      child.kill('SIGTERM');
      const force = setTimeout(() => child.kill('SIGKILL'), 1000);
      await exited;
      clearTimeout(force);
    }
  }
}

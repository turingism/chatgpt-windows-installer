'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const psPath = path.join(root, 'Install-ChatGPT.ps1');
const cmdPath = path.join(root, 'Install-ChatGPT.cmd');
const readmePath = path.join(root, 'README.md');
const readmeZhCnPath = path.join(root, 'README.zh-CN.md');
const readmeZhTwPath = path.join(root, 'README.zh-TW.md');

const ps = fs.readFileSync(psPath, 'utf8');
const cmd = fs.readFileSync(cmdPath, 'utf8');
const readme = fs.readFileSync(readmePath, 'utf8');
const readmeZhCn = fs.readFileSync(readmeZhCnPath, 'utf8');
const readmeZhTw = fs.readFileSync(readmeZhTwPath, 'utf8');

const failures = [];

function requireText(content, needle, label) {
  if (!content.includes(needle)) {
    failures.push(`缺少 ${label}: ${needle}`);
  }
}

function forbidText(content, pattern, label) {
  if (pattern.test(content)) {
    failures.push(`发现不应出现的 ${label}: ${pattern}`);
  }
}

function checkPowerShellDelimiters(source) {
  const pairs = { ')': '(', ']': '[', '}': '{' };
  const stack = [];
  let mode = 'code';

  for (let i = 0; i < source.length; i += 1) {
    const char = source[i];
    const next = source[i + 1];

    if (mode === 'line-comment') {
      if (char === '\n') mode = 'code';
      continue;
    }

    if (mode === 'block-comment') {
      if (char === '#' && next === '>') {
        mode = 'code';
        i += 1;
      }
      continue;
    }

    if (mode === 'single-quote') {
      if (char === "'" && next === "'") {
        i += 1;
      } else if (char === "'") {
        mode = 'code';
      }
      continue;
    }

    if (mode === 'double-quote') {
      if (char === '`') {
        i += 1;
      } else if (char === '"') {
        mode = 'code';
      } else if (char === '$' && next === '(') {
        stack.push({ char: '(', index: i + 1, interpolation: true });
        mode = 'code';
        i += 1;
      }
      continue;
    }

    if (char === '<' && next === '#') {
      mode = 'block-comment';
      i += 1;
      continue;
    }
    if (char === '#') {
      mode = 'line-comment';
      continue;
    }
    if (char === "'") {
      mode = 'single-quote';
      continue;
    }
    if (char === '"') {
      mode = 'double-quote';
      continue;
    }

    if ('([{'.includes(char)) {
      stack.push({ char, index: i, interpolation: false });
      continue;
    }
    if (')]}'.includes(char)) {
      const opening = stack.pop();
      if (!opening || opening.char !== pairs[char]) {
        failures.push(`PowerShell 分隔符不匹配，偏移 ${i}: ${char}`);
        return;
      }
      if (opening.interpolation) {
        mode = 'double-quote';
      }
    }
  }

  if (mode !== 'code' && mode !== 'line-comment') {
    failures.push(`PowerShell 结束时仍处于 ${mode} 状态`);
  }
  if (stack.length > 0) {
    const opening = stack[stack.length - 1];
    failures.push(`PowerShell 存在未闭合分隔符 ${opening.char}，偏移 ${opening.index}`);
  }
}

requireText(ps, '#requires -Version 5.1', 'Windows PowerShell 版本声明');
requireText(ps, "'9PLM9XGG6VKS'", 'ChatGPT Microsoft Store 产品 ID');
requireText(ps, 'ChatGPT-$Architecture.msix', '按架构选择的官方 MSIX');
requireText(ps, "'Git.Git'", 'Git 包');
requireText(ps, "'OpenJS.NodeJS.LTS'", 'Node.js LTS 包');
requireText(ps, "'Python.Python.3.14'", 'Python 包');
requireText(ps, "'Microsoft.DotNet.SDK.10'", '.NET SDK 包');
requireText(ps, "'GitHub.cli'", 'GitHub CLI 包');
requireText(ps, 'Add-AppxPackage -Path $msixPath', 'MSIX 安装回退');
requireText(ps, '--accept-source-agreements', 'WinGet 源协议参数');
requireText(ps, '--accept-package-agreements', 'WinGet 包协议参数');
requireText(ps, 'ConvertTo-Json -Depth 5', 'JSON 安装报告');
requireText(ps, "Write-ResultGroup -Title 'INSTALLED OR UPDATED'", '安装或更新成功清单');
requireText(ps, "Write-ResultGroup -Title 'FAILED'", '安装失败清单');
requireText(ps, "Write-ResultGroup -Title 'SKIPPED / PLANNED / ACTION REQUIRED'", '跳过和待处理清单');
requireText(ps, "'FINAL RESULT: SUCCESS - no component failed.'", '无失败最终结论');
requireText(ps, "$Status -in @('Failed', 'Unavailable')", '必需组件不可用时的失败判定');
requireText(ps, 'RequiredFailureCount = $requiredFailureCount', 'JSON 必需组件失败计数');
requireText(ps, 'FailedComponents = @($groups.Failed', 'JSON 失败组件清单');
requireText(ps, 'New-Object System.Text.UTF8Encoding($false)', '无 BOM UTF-8 控制台编码');
requireText(ps, '[Console]::InputEncoding = $utf8NoBom', 'PowerShell 控制台输入编码');
requireText(ps, '[Console]::OutputEncoding = $utf8NoBom', 'PowerShell 控制台输出编码');
requireText(ps, '$global:OutputEncoding = $utf8NoBom', 'PowerShell 原生命令管道编码');
requireText(cmd, 'chcp 65001 >nul', 'CMD UTF-8 代码页');
requireText(cmd, '-ExecutionPolicy Bypass -File "%~dp0Install-ChatGPT.ps1"', '双击启动命令');
requireText(readme, '%LOCALAPPDATA%\\OpenAI\\ChatGPTInstaller\\logs', '日志说明');
requireText(readme, '[简体中文](README.zh-CN.md)', '英文文档的简体中文链接');
requireText(readme, '[繁體中文](README.zh-TW.md)', '英文文档的繁体中文链接');
requireText(readmeZhCn, '[English](README.md)', '简体中文文档的英文链接');
requireText(readmeZhCn, '[繁體中文](README.zh-TW.md)', '简体中文文档的繁体中文链接');
requireText(readmeZhTw, '[English](README.md)', '繁体中文文档的英文链接');
requireText(readmeZhTw, '[简体中文](README.zh-CN.md)', '繁体中文文档的简体中文链接');

for (const [language, document] of [
  ['English', readme],
  ['zh-CN', readmeZhCn],
  ['zh-TW', readmeZhTw],
]) {
  requireText(document, '9PLM9XGG6VKS', `${language} 文档中的 Store 产品 ID`);
  requireText(document, 'Install-ChatGPT.cmd', `${language} 文档中的一键启动器`);
  requireText(document, '-Profile Complete', `${language} 文档中的 Complete 参数`);
  requireText(document, '-Profile Core', `${language} 文档中的 Core 参数`);
  requireText(document, '%LOCALAPPDATA%\\OpenAI\\ChatGPTInstaller\\logs', `${language} 文档中的日志路径`);
}

forbidText(ps, /winget\s+source\s+reset/i, 'WinGet 源重置');
forbidText(ps, /Set-ExecutionPolicy/i, '全局执行策略修改');
forbidText(ps, /-AllowUnsigned/i, '未签名包放行');
forbidText(ps, /Invoke-Expression|\biex\b/i, '动态代码执行');
forbidText(ps, /-IgnoreSecurityHash/i, '哈希校验绕过');

const invalidColonReferences = ps.match(
  /\$(?!script:|env:|global:|local:|private:|using:)[A-Za-z_][A-Za-z0-9_]*:/g,
);
if (invalidColonReferences) {
  failures.push(
    `发现 PowerShell 5.1 无效变量引用（变量后接冒号时应使用 \${变量}:）：${[...new Set(invalidColonReferences)].join(', ')}`,
  );
}

if (/[^\x00-\x7f]/.test(ps)) {
  failures.push('PowerShell 5.1 兼容脚本应保持 ASCII，避免无 BOM UTF-8 乱码');
}

checkPowerShellDelimiters(ps);

if (failures.length > 0) {
  console.error('静态检查失败：');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log('静态检查通过：必需组件、官方来源、安全约束和分隔符均符合预期。');

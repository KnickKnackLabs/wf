/** @jsxImportSource jsx-md */

import { execFileSync } from "child_process";
import { existsSync, readFileSync, readdirSync, statSync } from "fs";
import { join, resolve } from "path";

import {
  Badge,
  Badges,
  Bold,
  Cell,
  Center,
  Code,
  CodeBlock,
  Details,
  HR,
  Heading,
  Item,
  LineBreak,
  Link,
  List,
  Paragraph,
  Raw,
  Section,
  Sub,
  Table,
  TableHead,
  TableRow,
} from "readme";

const PROJECT = {
  name: "wf",
  oneLine: "Shell-native workflow primitives built from mise tasks.",
  tagline: "Route, branch, fan out, log, and supervise Unix pipelines without forcing a data format.",
  license: "MIT",
};

const REPO_DIR = resolve(import.meta.dirname);
const TASK_DIR = join(REPO_DIR, ".mise/tasks");
const TEST_DIR = join(REPO_DIR, "test");
const WORKFLOW = join(REPO_DIR, ".github/workflows/test.yml");

interface TaskInfo {
  name: string;
  description: string;
}

function read(path: string): string {
  return readFileSync(path, "utf8");
}

function walkFiles(dir: string, predicate: (path: string) => boolean): string[] {
  if (!existsSync(dir)) return [];

  const results: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...walkFiles(full, predicate));
    } else if (predicate(full)) {
      results.push(full);
    }
  }
  return results;
}

function discoverTasks(dir = TASK_DIR, prefix = ""): TaskInfo[] {
  if (!existsSync(dir)) return [];

  const tasks: TaskInfo[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    const full = join(dir, entry.name);
    const name = prefix ? `${prefix}:${entry.name}` : entry.name;

    if (entry.isDirectory()) {
      tasks.push(...discoverTasks(full, name));
      continue;
    }

    const mode = statSync(full).mode;
    if ((mode & 0o111) === 0) continue;

    const src = read(full);
    const description = src.match(/^#MISE description="(.+)"$/m)?.[1] ?? "";
    tasks.push({ name, description });
  }

  return tasks.sort((a, b) => a.name.localeCompare(b.name));
}

function countBatsTests(): number {
  return walkFiles(TEST_DIR, (path) => path.endsWith(".bats"))
    .map(read)
    .join("\n")
    .match(/@test\s+"/g)?.length ?? 0;
}

function configuredLints(): string[] {
  const miseToml = read(join(REPO_DIR, "mise.toml"));
  const start = miseToml.indexOf("[_.codebase]");
  if (start === -1) return [];

  const lines = miseToml.slice(start).split("\n");
  const block: string[] = [];
  for (const [index, line] of lines.entries()) {
    if (index > 0 && line.startsWith("[")) break;
    block.push(line);
  }

  const list = block.join("\n").match(/lint\s*=\s*\[([\s\S]*?)\]/)?.[1] ?? "";
  const configured = [...list.matchAll(/"([^"]+)"/g)].map((match) => match[1]);
  if (!configured.some((rule) => rule.startsWith("@"))) return configured;

  const memberships = new Map<string, string[]>();
  let currentGroup = "";
  const groups = execFileSync("codebase", ["lint:groups"], {
    cwd: REPO_DIR,
    encoding: "utf8",
  });
  for (const line of groups.split("\n")) {
    if (line.startsWith("@")) {
      currentGroup = line;
      memberships.set(currentGroup, []);
    } else if (currentGroup && line.startsWith("  ")) {
      memberships.get(currentGroup)!.push(line.trim());
    }
  }

  return [...new Set(configured.flatMap((rule) => memberships.get(rule) ?? [rule]))];
}

function workflowOses(): string[] {
  if (!existsSync(WORKFLOW)) return [];
  const match = read(WORKFLOW).match(/os:\s*\[([^\]]+)\]/);
  if (!match) return [];
  return match[1].split(",").map((os) => os.trim()).filter(Boolean);
}

function wfTaskName(taskName: string): string {
  return taskName.split(":").join(" ");
}

const tasks = discoverTasks();
const testCount = countBatsTests();
const lints = configuredLints();
const oses = workflowOses();

const layout = [
  ["bin/wf", "binary shim that resolves space-separated task names"],
  [".mise/tasks/", "workflow primitives; nested paths become nested wf commands"],
  ["lib/wf.bash", "shared Bash helpers for task scripts"],
  ["test/", "BATS tests that exercise the shim"],
  ["README.tsx", "generated README source"],
  ["mise.toml", "tools, settings, and convention lint config"],
];

const readme = (
  <>
    <Center>
      <Heading level={1}>{PROJECT.name}</Heading>

      <Paragraph>
        <Bold>{PROJECT.oneLine}</Bold>
      </Paragraph>

      <Paragraph>{PROJECT.tagline}</Paragraph>

      <Badges>
        <Badge label="shape" value="mise tasks + Bash" color="4EAA25" logo="gnubash" logoColor="white" />
        <Badge label="tests" value={`${testCount}`} color="brightgreen" href="test/" />
        <Badge label="tasks" value={`${tasks.length}`} color="blue" href=".mise/tasks/" />
        <Badge label="README" value="TSX" color="f472b6" />
        <Badge label="License" value={PROJECT.license} color="blue" href="LICENSE" />
      </Badges>
    </Center>

    <LineBreak />

    <Section title="What this is">
      <Paragraph>
        <Code>wf</Code>
        {" is an experiment in n8n-like workflow composition using ordinary shell pieces. The public interface is a tiny binary shim, "}
        <Code>bin/wf</Code>
        {", that maps commands like "}
        <Code>wf cond if</Code>
        {" to mise task scripts like "}
        <Code>.mise/tasks/cond/if</Code>
        {"."}
      </Paragraph>

      <Paragraph>
        {"The core does "}
        <Bold>not</Bold>
        {" require JSON, CSV, or any other data format. It treats stdin/stdout as streams, and the first practical record framing is line-oriented. Format-specific helpers live under namespaces such as "}
        <Code>wf text</Code>
        {" and "}
        <Code>wf json</Code>
        {"."}
      </Paragraph>
    </Section>

    <Section title="Core model">
      <List>
        <Item><Bold>Transport:</Bold> stdin/stdout/stderr, normal Unix pipes, and background processes.</Item>
        <Item><Bold>Framing:</Bold> v0 primitives operate on line records unless a task says otherwise, including a final record without a trailing newline.</Item>
        <Item><Bold>Encoding:</Bold> unrestricted by default; text and JSON helpers are optional layers.</Item>
        <Item><Bold>Commands:</Bold> command arguments are explicit shell snippets run by Bash, so quote them like any other shell code.</Item>
        <Item><Bold>State:</Bold> background runs live under <Code>$WF_STATE_HOME</Code> when set, otherwise <Code>$XDG_STATE_HOME/wf</Code> or <Code>~/.local/state/wf</Code>.</Item>
        <Item><Bold>Tasks:</Bold> every node is a Bash script under <Code>.mise/tasks</Code>.</Item>
      </List>
    </Section>

    <Section title="Workflow graph patterns">
      <Paragraph>
        {"Some nodes are "}
        <Bold>sources</Bold>
        {" and do not consume stdin. For example, "}
        <Code>wf emit alpha beta gamma | wf tick</Code>
        {" prints ticks forever by default; the emitted words are not part of the downstream flow. For large or short-lived combinations, piping into a source can block or trip SIGPIPE because nothing drains the pipe."}
      </Paragraph>

      <Paragraph>
        {"Fan-out sends one stream to multiple branches; fan-in merges multiple source commands into one stream. Concurrent fan-in has intentionally nondeterministic ordering, so tests should sort or otherwise normalize when order is not part of the contract."}
      </Paragraph>

      <CodeBlock lang="bash">{`wf fanin merge \\
  'wf tick --count 3 every 0s | sed "s/^/tick:/"' \\
  'wf emit alpha beta | sed "s/^/word:/"' \\
  | wf fanout tee --pass \\
      'wf log append all.log --sink' \\
  | wf text select '^tick:'`}</CodeBlock>

      <Paragraph>
        {"For larger workflows, prefer a small Bash script with named command strings/functions over a single unreadable one-liner."}
      </Paragraph>
    </Section>

    <Section title="Tooling dependencies">
      <Paragraph>
        <Code>mise install</Code>
        {" installs the project tools, including "}
        <Code>jq</Code>
        {" for "}
        <Code>wf json</Code>
        {" helpers. Core text, condition, flow, fanout, logging, and run primitives stay Bash/Unix-stream oriented."}
      </Paragraph>
    </Section>

    <Section title="Quick start">
      <CodeBlock lang="bash">{`mise trust
mise install

./bin/wf help
./bin/wf help tick
./bin/wf tick --count 5 every 0s`}</CodeBlock>
    </Section>

    <Section title="Examples">
      <Paragraph>Route plain text numbers without assuming JSON:</Paragraph>
      <CodeBlock lang="bash">{`wf tick --count 5 every 0s \\
  | wf text if '^[02468]$' \\
      --then 'sed "s/^/even: /"' \\
      --else 'sed "s/^/odd: /"'`}</CodeBlock>

      <Paragraph>Use a generic predicate command when regex is not enough:</Paragraph>
      <CodeBlock lang="bash">{`wf emit 1 2 3 4 \\
  | wf cond select 'awk "{ exit !(\\$1 > 2) }"'`}</CodeBlock>

      <Paragraph>Opt into JSONL only when structured predicates are useful:</Paragraph>
      <CodeBlock lang="bash">{`wf tick --count 3 --format json every 0s \\
  | wf json select '.n >= 2'`}</CodeBlock>

      <Paragraph>Start, inspect, log, and stop a named background workflow:</Paragraph>
      <CodeBlock lang="bash">{`wf run start demo -- 'wf tick every 5s | wf log pretty'
wf run status demo
wf run logs -f demo
wf run stop demo`}</CodeBlock>
    </Section>

    <Section title="Repository layout">
      <Table>
        <TableHead>
          <Cell>Path</Cell>
          <Cell>Purpose</Cell>
        </TableHead>
        {layout.map(([path, purpose]) => (
          <TableRow>
            <Cell><Code>{path}</Code></Cell>
            <Cell>{purpose}</Cell>
          </TableRow>
        ))}
      </Table>
    </Section>

    <Section title="Tasks">
      <Table>
        <TableHead>
          <Cell>Command</Cell>
          <Cell>Description</Cell>
        </TableHead>
        {tasks.map((task) => (
          <TableRow>
            <Cell><Code>{`wf ${wfTaskName(task.name)}`}</Code></Cell>
            <Cell>{task.description}</Cell>
          </TableRow>
        ))}
      </Table>
    </Section>

    <Section title="Development notes">
      <List ordered>
        <Item>Keep core primitives format-agnostic unless the namespace says otherwise.</Item>
        <Item>Prefer line-oriented tasks first; add stronger framing only when a real workflow needs it.</Item>
        <Item>Use <Code>$MISE_CONFIG_ROOT</Code> for repo-relative paths inside tasks.</Item>
        <Item>Use <Code>$WF_CALLER_PWD</Code> when a task needs the directory where the user invoked <Code>wf</Code>; resolve user-facing relative file paths from there.</Item>
        <Item>Write tests through <Code>bin/wf</Code>, not by invoking task scripts directly.</Item>
      </List>
    </Section>

    <Details summary="Current convention checks">
      <Paragraph>
        <Code>wf</Code>
        {" currently asks "}
        <Link href="https://github.com/KnickKnackLabs/codebase">codebase</Link>
        {" to run these lint rules:"}
      </Paragraph>
      <CodeBlock>{lints.join("\n")}</CodeBlock>
    </Details>

    <Section title="Validation">
      <CodeBlock lang="bash">{`mise run test
codebase lint "$PWD"
readme build --check
git diff --check`}</CodeBlock>

      <Paragraph>
        {"The suite currently has "}
        <Bold>{`${testCount} tests`}</Bold>
        {", "}
        <Bold>{`${tasks.length} executable tasks`}</Bold>
        {", and CI runs on "}
        <Bold>{oses.join(" + ") || "configured OSes"}</Bold>
        {"."}
      </Paragraph>
    </Section>

    <Center>
      <HR />
      <Sub>
        {"This README was generated from "}
        <Code>README.tsx</Code>
        {" with "}
        <Link href="https://github.com/KnickKnackLabs/readme">KnickKnackLabs/readme</Link>
        {"."}
        <Raw>{"<br />"}</Raw>
        {"Streams first, structure when useful."}
      </Sub>
    </Center>
  </>
);

console.log(readme);

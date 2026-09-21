/** ============================================================================
  *  ShellAuditSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/agentbench/ShellAuditSpec.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  Pins the shell arm's confinement audit (issue #162).  The shell arm cannot
  *  be confined by the client (`--restricted` confines the file tools, never
  *  Bash), so confinement is an audit over the paths each Bash command names,
  *  and the audit is only worth the name if it is conservative: a command this
  *  reader cannot account for is a violation, never a pass.  These cases are
  *  written before the parser and fix its direction.
  *
  *  The escapes that must fail
  *  --------------------------
  *  A read or write outside the roots, a `cd` out of the work directory, a
  *  here-doc written outside it, a program this audit does not model, a shell
  *  construct it cannot see through (command substitution, variable
  *  expansion), and an unterminated quote.
  *
  *  The work that must pass
  *  -----------------------
  *  The judge's own `agda` invocation, `agda --interaction-json` driven from a
  *  here-doc, a corpus grep, a library-source read, and the ordinary text
  *  plumbing around them, so a legitimate shell subject is not failed for
  *  doing what the arm exists to measure.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import java.nio.file.Paths
import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers

final class ShellAuditSpec extends AnyFunSuite with Matchers {

  private val work    = Paths.get("/run/work/stdlib-nat-plus-comm")
  private val stdlib  = Paths.get("/nix/store/aaa-standard-library-2.3/src")
  private val dojang  = Paths.get("/repo/agda-dojang/agda")
  private val agdaDir = Paths.get("/repo/agda")
  private val corpus  = Paths.get("/repo/data/corpora/agda-stdlib/v0/corpus.jsonl")
  private val roots   = ShellRoots(work, Vector(stdlib, dojang, agdaDir), Vector(corpus))

  private def bad(cmd: String): Vector[String] = ShellAudit.inspect(cmd, roots).violations
  private def ok(cmd: String): Unit            = withClue(s"expected no violation for: $cmd\n") { bad(cmd) shouldBe Vector.empty }
  private def cls(cmd: String): String         = ShellAudit.inspect(cmd, roots).commandClass

  // ---------------------------------------------------------------- escapes

  test("a read outside every root is a violation naming the path") {
    bad("cat /etc/passwd").size shouldBe 1
    bad("cat /etc/passwd").head should include ("/etc/passwd")
    bad("cat ../gold/Nat.agda").head should include ("gold")
    bad("cat ..").size shouldBe 1
    bad("cat ~/.ssh/id_rsa").size shouldBe 1
    bad("grep -r x /repo/data/benchmarks/agda-stdlib-v0/gold").size shouldBe 1   // the answer key
  }

  test("a write outside the work directory is a violation, redirections included") {
    bad("echo x > /tmp/out").head should include ("/tmp/out")
    bad("echo x >> /tmp/out").size shouldBe 1
    bad("agda M.agda 2> /tmp/log").size shouldBe 1
    // A write into a read-only root is refused too: the library is not ours to edit.
    bad(s"echo x > $stdlib/Data/Nat/Properties.agda").size shouldBe 1
    bad(s"cp M.agda $stdlib/M.agda").size shouldBe 1                             // destination outside
    bad("rm ../M.agda").size shouldBe 1
    bad(s"sed -i s/a/b/ $stdlib/Data/Nat/Base.agda").size shouldBe 1             // in place, outside
  }

  test("a here-doc written outside the work directory is a violation; its body is data, not paths") {
    bad("cat > /tmp/script.sh <<'EOF'\ncat /etc/passwd\nEOF").size shouldBe 1
    bad("cat > /tmp/script.sh <<'EOF'\ncat /etc/passwd\nEOF").head should include ("/tmp/script.sh")
    // The same here-doc written inside the work directory is one violation, not two:
    // the body's `/etc/passwd` is input to the program, never a path the shell opens.
    ok("cat > notes.txt <<'EOF'\nsee /etc/passwd\nEOF")
  }

  test("changing the working directory is a violation unless it is the work directory itself") {
    bad("cd .. && cat M.agda").size should be >= 1
    bad("cd /etc && ls").size should be >= 1
    bad("cd ..; cat ../gold/Nat.agda").size should be >= 1
    ok(s"cd $work && agda --version")
  }

  test("a program this audit does not model is a violation, named with its command") {
    bad("python3 -c 'print(open(\"/etc/passwd\").read())'").size shouldBe 1
    bad("python3 -c 'print(1)'").head should include ("python3")
    bad("bash run.sh").size shouldBe 1
    bad("xargs cat < list.txt").size should be >= 1
    bad("env AGDA_DIR=/x agda M.agda").size should be >= 1
    bad("for f in *.agda; do cat $f; done").size should be >= 1
    bad(s"find $stdlib -name '*.agda' -exec cat {} ;").size should be >= 1
  }

  test("a construct the reader cannot see through is a violation, not a pass") {
    bad("cat $(ls ..)").size should be >= 1
    bad("cat `ls ..`").size should be >= 1
    bad("cat $HOME/.ssh/id_rsa").size should be >= 1
    bad("cat \"$SECRET\"").size should be >= 1
    bad("cat 'unterminated").size should be >= 1
    // A dollar inside single quotes is literal, so an anchored pattern is not an expansion.
    ok(s"grep 'comm$$' $corpus")
  }

  test("every violation names the command, so the report can quote what failed the gate") {
    bad("cat /etc/passwd").head should include ("cat /etc/passwd")
  }

  // ---------------------------------------------------------------- the work

  test("the judge's own agda invocation passes and classes as a batch check") {
    val cmd = s"agda --no-default-libraries --library-file $agdaDir/libraries --library standard-library " +
      s"--library agda-dojang --safe -i $work $work/Nat-plus-comm.agda"
    ok(cmd)
    cls(cmd) shouldBe "agda-batch"
    ok("agda --safe -i . Nat-plus-comm.agda")
    cls("agda --safe -i . Nat-plus-comm.agda") shouldBe "agda-batch"
    ok("agda M.agda 2>&1 | tail -40")
    ok("agda M.agda > out.log 2>&1")
    ok("agda M.agda 2> /dev/null")                                   // the sinks are allowed
  }

  test("agda --interaction-json driven from a here-doc passes and is its own class") {
    val cmd = "agda --interaction-json --no-default-libraries --library standard-library <<'EOF'\n" +
      "IOTCM \"/run/work/stdlib-nat-plus-comm/M.agda\" None Direct (Cmd_load \"/run/work/stdlib-nat-plus-comm/M.agda\" [])\n" +
      "EOF"
    ok(cmd)
    cls(cmd) shouldBe "agda-interaction"
    ok("printf 'IOTCM ...' | agda --interaction-json")
    cls("printf 'IOTCM ...' | agda --interaction-json") shouldBe "agda-interaction"
  }

  test("a corpus grep and a library-source read pass, and each has its class") {
    ok(s"grep -m 5 '\"name\":\"+-comm\"' $corpus")
    cls(s"grep -m 5 '\"name\":\"+-comm\"' $corpus") shouldBe "corpus-grep"
    ok(s"jq -r 'select(.name==\"+-comm\")' $corpus | head -5")
    cls(s"jq -r 'select(.name==\"+-comm\")' $corpus | head -5") shouldBe "corpus-grep"
    ok(s"cat $stdlib/Data/Nat/Properties.agda")
    cls(s"cat $stdlib/Data/Nat/Properties.agda") shouldBe "library-read"
    ok(s"sed -n '1,80p' $dojang/AgdaDojang/Debug.agda")
    cls(s"sed -n '1,80p' $dojang/AgdaDojang/Debug.agda") shouldBe "library-read"
    ok(s"grep -rn 'identityL' $stdlib/Data/Nat")
    ok(s"ls $stdlib/Data/Nat")
    // The class of a call is the first that applies, so an agda run over a
    // library path is still an agda run.
    cls(s"agda -i $stdlib M.agda") shouldBe "agda-batch"
  }

  test("ordinary work inside the work directory passes") {
    ok("ls")
    ok("ls -la")
    ok("cat M.agda")
    ok("pwd")
    ok("wc -l M.agda")
    ok("diff M.agda M.agda.bak")
    ok("cp M.agda M.agda.bak")
    ok("mkdir scratch && cp M.agda scratch/")
    ok("echo 'note' > notes.txt")
    ok("grep -n 'identityL' M.agda")
    ok("head -20 M.agda; tail -20 M.agda")
    ok("cat M.agda | grep -n hole | head -3")
    cls("ls") shouldBe "other"
  }

  // ---------------------------------------------------------------- shapes

  test("the classes are exhaustive and a call has exactly one, so they sum to the Bash calls") {
    ShellAudit.classes should contain allOf ("agda-batch", "agda-interaction", "corpus-grep", "library-read", "other")
    val cmds = Vector("agda M.agda", "agda --interaction-json", s"grep x $corpus", s"cat $stdlib/X.agda", "ls", "cat /etc/passwd")
    cmds.map(cls).foreach(c => ShellAudit.classes should contain (c))
    cmds.map(cls).distinct.size should be > 1
  }

  test("the corpus is matched through a symlink too, since the corpora are symlinked into a worktree") {
    val real  = Paths.get("/other/worktree/data/corpora/agda-stdlib/v0/corpus.jsonl")
    val both  = roots.copy(corpora = Vector(corpus, real))
    ShellAudit.inspect(s"grep x $real", both).violations shouldBe Vector.empty
    ShellAudit.inspect(s"grep x $real", both).commandClass shouldBe "corpus-grep"
  }
}

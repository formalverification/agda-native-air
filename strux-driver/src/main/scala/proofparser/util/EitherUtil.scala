package proofparser.util

import scala.util.{Try, Success, Failure}
import scala.util.control.NonFatal

object EitherUtil {
  def catchNonFatal[A](thunk: => A): Either[String, A] =
    try Right(thunk)
    catch { case NonFatal(e) => Left(e.getMessage) }
}

/*
 * CDDL HEADER START
 *
 * The contents of this file are subject to the terms of the
 * Common Development and Distribution License (the "License").  
 * You may not use this file except in compliance with the License.
 *
 * See LICENSE.txt included in this distribution for the specific
 * language governing permissions and limitations under the License.
 *
 * When distributing Covered Code, include this CDDL HEADER in each
 * file and include the License file at LICENSE.txt.
 * If applicable, add the following below this CDDL HEADER, with the
 * fields enclosed by brackets "[]" replaced with your own identifying
 * information: Portions Copyright [yyyy] [name of copyright owner]
 *
 * CDDL HEADER END
 */

/*
 * Copyright (c) 2017, Oracle and/or its affiliates. All rights reserved.
 * Portions Copyright (c) 2017, Chris Fraire <cfraire@me.com>.
 */

package org.opensolaris.opengrok.analysis.kotlin;

import org.opensolaris.opengrok.analysis.JFlexXrefSimple;
import org.opensolaris.opengrok.util.StringUtils;
import org.opensolaris.opengrok.web.HtmlConsts;
import org.opensolaris.opengrok.web.Util;
%%
%public
%class KotlinXref
%extends JFlexXrefSimple
%unicode
%ignorecase
%int
%include CommonXref.lexh
%{
  /* Must match {WhiteSpace} regex */
  private final static String WHITE_SPACE = "[ \\t\\f]+";

  private int nestedComment;

  @Override
  public void reset() {
      super.reset();
      nestedComment = 0;
  }

  // TODO move this into an include file when bug #16053 is fixed
  @Override
  protected int getLineNumber() { return yyline; }
  @Override
  protected void setLineNumber(int x) { yyline = x; }
%}

File = [a-zA-Z]{FNameChar}* "." ([Jj][Aa][Vv][Aa] |
    [Pp][Rr][Oo][Pp][Ee][Rr][Tt][Ii][Ee][Ss] | [Pp][Rr][Oo][Pp][Ss] |
    [Xx][Mm][Ll] | [Cc][Oo][Nn][Ff] | [Tt][Xx][Tt] | [Hh][Tt][Mm][Ll]? |
    [Ii][Nn][Ii] | [Jj][Nn][Ll][Pp] | [Jj][Aa][Dd] | [Dd][Ii][Ff][Ff] |
    [Pp][Aa][Tt][Cc][Hh])

KdocWithClassArg = "@throws" | "@exception"
KdocWithParamNameArg = "@param"

ClassName = ({Identifier} ".")* {Identifier}
ParamName = {Identifier} | "<" {Identifier} ">"

%state  STRING COMMENT SCOMMENT QSTRING KDOC TSTRING

%include Common.lexh
%include CommonURI.lexh
%include CommonPath.lexh
%include Kotlin.lexh
%%
<YYINITIAL>{
 \{     { incScope(); writeUnicodeChar(yycharat(0)); }
 \}     { decScope(); writeUnicodeChar(yycharat(0)); }
 \;     { endScope(); writeUnicodeChar(yycharat(0)); }

{Identifier} {
    String id = yytext();
    writeSymbol(id, Consts.kwd, yyline);
}

"<" ({File}|{FPath}) ">" {
        out.write("&lt;");
        String path = yytext();
        path = path.substring(1, path.length() - 1);
        out.write("<a href=\""+urlPrefix+"path=");
        out.write(path);
        appendProject();
        out.write("\">");
        out.write(path);
        out.write("</a>");
        out.write("&gt;");
}

 {Number}        {
    disjointSpan(HtmlConsts.NUMBER_CLASS);
    out.write(yytext());
    disjointSpan(null);
 }

 \"     {
    pushSpan(STRING, HtmlConsts.STRING_CLASS);
    out.write(htmlize(yytext()));
 }
 \'     {
    pushSpan(QSTRING, HtmlConsts.STRING_CLASS);
    out.write(htmlize(yytext()));
 }
 \"\"\"    {
    pushSpan(TSTRING, HtmlConsts.STRING_CLASS);
    out.write(htmlize(yytext()));
 }
 "/**" / [^/]    {
    if (nestedComment++ == 0) {
        pushSpan(KDOC, HtmlConsts.COMMENT_CLASS);
    }
    out.write(yytext());
 }
 "//"    {
    pushSpan(SCOMMENT, HtmlConsts.COMMENT_CLASS);
    out.write(yytext());
 }
}

<STRING> {
 \\[\"\$\\]    { out.write(htmlize(yytext())); }
 \"     {
    out.write(htmlize(yytext()));
    yypop();
 }
}

<QSTRING> {
 \\[\'\\] |
 \' {WhiteSpace} \' { out.write(htmlize(yytext())); }
 \'     {
    out.write(htmlize(yytext()));
    yypop();
 }
}

<TSTRING> {
 /*
  * "raw string ... doesn't support backslash escaping"
  */
 \"\"\"    {
    out.write(htmlize(yytext()));
    yypop();
 }
}

<STRING, TSTRING> {
    /*
     * TODO : support template expressions inside curly brackets
     */
    \$ {Identifier}    {
        String capture = yytext();
        String sigil = capture.substring(0, 1);
        String id = capture.substring(1);
        out.write(sigil);
        disjointSpan(null);
        writeSymbol(id, Consts.kwd, yyline);
        disjointSpan(HtmlConsts.STRING_CLASS);
    }
    {WhspChar}*{EOL}    {
        disjointSpan(null);
        startNewLine();
        disjointSpan(HtmlConsts.STRING_CLASS);
    }
}

<YYINITIAL, COMMENT, KDOC> {
    "/*"    {
        if (nestedComment++ == 0) {
            pushSpan(COMMENT, HtmlConsts.COMMENT_CLASS);
        }
        out.write(yytext());
    }
}

<COMMENT, KDOC> {
"*/"    {
    out.write(yytext());
    if (--nestedComment == 0) {
        yypop();
    }
 }
 {WhspChar}*{EOL}    {
    disjointSpan(null);
    startNewLine();
    disjointSpan(HtmlConsts.COMMENT_CLASS);
 }
}

<KDOC> {
  {KdocWithParamNameArg} {WhiteSpace} {ParamName} |
  {KdocWithClassArg} {WhiteSpace} {ClassName} {
    String text = yytext();
    String[] tokens = text.split(WHITE_SPACE, 2);
    out.append("<strong>").append(tokens[0]).append("</strong>")
      .append(text.substring(tokens[0].length(),
                             text.length() - tokens[1].length()))
      .append("<em>").append(tokens[1]).append("</em>");
  }
  "@" {Identifier} {
    out.append("<strong>").append(yytext()).append("</strong>");
  }
}

<SCOMMENT> {
  {WhspChar}*{EOL} {
    yypop();
    startNewLine();
  }
}


<YYINITIAL, STRING, COMMENT, SCOMMENT, QSTRING, KDOC, TSTRING> {
[&<>\'\"]    { out.write(htmlize(yytext())); }

{WhspChar}*{EOL}      { startNewLine(); }
 {WhiteSpace}   { out.write(yytext()); }
 [!-~]  { out.write(yycharat(0)); }
 [^\n]      { writeUnicodeChar(yycharat(0)); }
}

<STRING, COMMENT, SCOMMENT, QSTRING, TSTRING, KDOC> {
{FPath}
        { out.write(Util.breadcrumbPath(urlPrefix+"path=",yytext(),'/'));}

{File}
        {
        String path = yytext();
        out.write("<a href=\""+urlPrefix+"path=");
        out.write(path);
        appendProject();
        out.write("\">");
        out.write(path);
        out.write("</a>");}

{FNameChar}+ "@" {FNameChar}+ "." {FNameChar}+
        {
          writeEMailAddress(yytext());
        }
}

<STRING, SCOMMENT, QSTRING, TSTRING> {
    {BrowseableURI}    {
        appendLink(yytext(), true);
    }
}

<COMMENT, KDOC> {
    {BrowseableURI}    {
        appendLink(yytext(), true, StringUtils.END_C_COMMENT);
    }
}

import std.algorithm : map, uniq, sort;
import std.stdio : writeln, writefln, File;
import std.file : read;
import std.conv : to;
import std.array : appender, Appender;
import std.range : drop;
import std.format : formattedWrite, format;
import std.uni : toUpper;

import std.logger;

import stack;
import dropuntil;
import xmltokenrange;

struct UnderscoreCap {
	string data;
	bool capNext;
	bool isFirst;

	@property dchar front() pure @safe {
		if(capNext || isFirst) {
			return std.uni.toUpper(data.front);
		} else {
			return data.front;
		}
	}

	@property bool empty() pure @safe nothrow {
		return data.empty;
	}

	@property void popFront() {
		if(!data.empty()) {
			isFirst = false;
			data.popFront();
			if(!data.empty() && data.front == '_') {
				capNext = true;
				data.popFront();
			} else {
				capNext = false;
			}
		}
	}
}

UnderscoreCap underscoreCap(IRange)(IRange i) {
	UnderscoreCap r;
	r.isFirst = true;
	r.data = i;
	return r;
}

unittest {
	auto s = "hello_world";
	auto sm = underscoreCap(s);
	assert(to!string(sm) == "HelloWorld", to!string(sm));
}

enum BinType {
	Invalid,
	Box,
	Notebook
}

struct Obj {
	BinType type;
	string obj;
	string cls;

	static Obj opCall(string o, string c) {
		Obj ret;
		ret.obj = o;
		ret.cls = c;
		switch(c) {
			case "GtkNotebook":
				ret.type = BinType.Notebook;
				break;
			default:
				ret.type = BinType.Box;
		}
		return ret;
	}

	string toAddFunction() pure @safe nothrow {
		final switch(this.type) {
			case BinType.Invalid: return "INVALID_BIN_TYPE";
			case BinType.Box: return "add";
			case BinType.Notebook: return "appendPage";
		}
	}

	string toName() pure @safe nothrow {
		if(this.obj == "placeholder") {
			return "new HBox()";
		} else {
			return this.obj;
		}
	}
}

void setupObjects(ORange,IRange)(ref ORange o, IRange i) {
	string curObject = "this";
	string curProperty;
	bool translateable;
	bool notebook = false;
	bool dontCloseObject = false;
	Stack!Obj objStack;

	foreach(it; i.drop(1)) {
		infoF("%s %s %s", it.kind, it.kind == XmlTokenKind.Open || it.kind ==
			XmlTokenKind.Close || it.kind == XmlTokenKind.OpenClose ? 
			it.name : "", !objStack.empty ? objStack.top().obj : ""
		);
		if(it.kind == XmlTokenKind.Open && it.name == "object" ||
				it.kind == XmlTokenKind.OpenClose && it.name == "placeholder") {

			bool placeHolder = false;
			if(it.kind == XmlTokenKind.OpenClose && it.name == "placeholder") {
				warning();
				placeHolder = true;
			}

			curObject = it["id"];
			if(notebook) {
				Obj widget;
				if(!placeHolder) {
			   		widget = objStack.top();
					objStack.pop();
				} else {
					widget = Obj("placeholder", "GtkHBox");
				}
				o.formattedWrite("\t\t%s.%s(this.%s, this.%s);\n", 
					objStack.top().obj, objStack.top().toAddFunction(), 
					widget.obj, curObject
				);
				notebook = false;
				dontCloseObject = false;
			} else if(!objStack.empty) {
				if(objStack.top().type != BinType.Notebook) {
					o.formattedWrite("\t\t%s.%s(this.%s);\n",
						objStack.top().toName(),
						objStack.top().toAddFunction(), curObject
					);
				} else {
					notebook = true;
					dontCloseObject = true;
				}
			}
			objStack.push(Obj(curObject, it["class"]));
			traceF("stack open size %u", objStack.length);
		} else if(it.kind == XmlTokenKind.Close && it.name == "object") {
			if(!dontCloseObject) {
				objStack.pop();
				traceF("stack close size %u", objStack.length);
			}
		} else if(it.kind == XmlTokenKind.Open && it.name == "property") {
			curProperty = it["name"];
			if(curProperty == "label" && it.attributes.contains("translatable")) 
			{
				translateable = it["translatable"] == "yes";
			}
		} else if(it.kind == XmlTokenKind.Open && it.name == "child") {
			traceF("stack open size %u", objStack.length);
		} else if(it.kind == XmlTokenKind.Close && it.name == "child") {
		} else if(it.kind == XmlTokenKind.Text) {
			traceF("%s", it.data);
			if(curProperty == "label") {
				trace();
				o.formattedWrite("\t\t%s.set%s(\"%s\");\n", curObject,
					underscoreCap(curProperty), 
					it.data
				);
			} else if(it.data == "True" || it.data == "False") {
				trace();
				o.formattedWrite("\t\t%s.set%s(%s);\n", curObject,
					underscoreCap(curProperty), 
					it.data == "True" ? "true" : "false"
				);
			}
		}
	}
}

void createObjects(ORange,IRange)(ref ORange o, IRange i) {
	o.formattedWrite("\tthis() {\n");
	foreach(it; i) {
		if(it.kind == XmlTokenKind.Open && it.name == "object") {
			o.formattedWrite("\t\tthis.%s = new %s();\n", it["id"], 
				it["class"][3 .. $]
			);
		}
	}
	o.formattedWrite("\n");
	setupObjects(o, i);
	o.formattedWrite("\t}\n\n");
}

void main() {
	LogManager.globalLogLevel = LogLevel.info;
	string input = cast(string)read("test1.glade");
	auto tokenRange = input.xmlTokenRange();
	auto payLoad = tokenRange.dropUntil!(a => a.kind == XmlTokenKind.Open && 
		a.name == "object" && a.attributes.contains("class") && 
		(a["class"] == "GtkWindow")
	);

	XmlToken clsType;
	auto elem = appender!(XmlToken[])();
	clsType = payLoad.front;
	foreach(it; payLoad.drop(1)) {
		if(it.kind == XmlTokenKind.Open && it.name == "object") {
			elem.put(it);
		}
	}

	foreach(ref XmlToken it; elem.data()) {
		logF("%s %s %s", it.name, it["class"], it["id"]);
	}

	log();

	auto of = File("output.d", "w");
	auto ofr = of.lockingTextWriter();

	string moduleName = "somemodule";
	string className = "SomeClass";

	ofr.formattedWrite("module %s;\n\n", moduleName);
	log();

	auto names = elem.data.map!(a => a["class"]);
	auto usedTypes = names.array.sort.uniq;
	foreach(it; usedTypes) {
		ofr.formattedWrite("import gtk.%s;\n", it[3 .. $]);
	}

	logF("%u ", clsType.attributes.length);

	ofr.formattedWrite("\nabstract class %s : %s {\n", className,
		clsType["class"]
	);

	log();
	createObjects(ofr, payLoad);
}

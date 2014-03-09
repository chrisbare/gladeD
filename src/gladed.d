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
	string curProperty;
	bool translateable;
	Stack!Obj objStack;
	objStack.push(Obj("this", "GtkWindow"));
	Stack!Obj childStack;

	foreach(it; i.drop(1)) {
		infoF(false, "%s %s %s", it.kind, it.kind == XmlTokenKind.Open || it.kind ==
			XmlTokenKind.Close || it.kind == XmlTokenKind.OpenClose ? 
			it.name : "", !objStack.empty ? objStack.top().obj : ""
		);

		if(it.kind == XmlTokenKind.Open && it.name == "object") {
			infoF("%s %s", it.name, it["class"]);
			objStack.push(Obj(it["id"], it["class"]));
		} else if(it.kind == XmlTokenKind.Close && it.name == "object" ||
				it.kind == XmlTokenKind.OpenClose && it.name == "placeholder") {
			Obj ob;
			if(it.kind == XmlTokenKind.Close && it.name == "object") {
				infoF("%s %s", objStack.top().obj, objStack.top().cls);
				assert(!objStack.empty());
				ob = objStack.top();
				objStack.pop();
				if(ob.obj == "this") {
					break;
				}
			} else {
				info("Placeholder");
				ob = Obj("new Box()", "GtkBox");
			}
			assert(!objStack.empty());
			infoF("%s %s %u", objStack.top().obj, objStack.top().cls,
				childStack.length
			);
			if(objStack.top().cls == "GtkNotebook") {
				if(!childStack.empty()) {
					auto ob2 = childStack.top();
					childStack.pop();
					o.formattedWrite("\t\t%s.appendPage(%s, this.%s);\n\n", 
						objStack.top().obj, ob2.obj, ob.obj
					);
				} else {
					childStack.push(ob);
				}
			} else {
				assert(!objStack.empty());
				o.formattedWrite("\t\t%s.add(this.%s);\n\n", 
					objStack.top().obj, ob.obj
				);
			}
		} else if(it.kind == XmlTokenKind.Open && it.name == "property") {
			curProperty = it["name"];
		} else if(it.kind == XmlTokenKind.Text) {
			if(it.data == "False" || it.data == "True") {
				o.formattedWrite("\t\t%s.set%s(%s);\n", objStack.top().obj,
					underscoreCap(curProperty), it.data == "True" ? "true" :
					"false"
				);
			} else if(curProperty != "orientation") {
				o.formattedWrite("\t\t%s.set%s(\"%s\");\n", objStack.top().obj,
					underscoreCap(curProperty), it.data
				);
			}
		}
	}
}

string getBoxOrientation(IRange)(IRange i) {
	foreach(it; i) {
		infoF(it.kind == XmlTokenKind.Text, "%s %b", it.data, it.data ==
				"vertical");
		if(it.kind == XmlTokenKind.Text && it.data == "vertical") {
			info();
			return it.data;
		} else if(it.kind == XmlTokenKind.Text && it.data == "horizontal") {
			return it.data;
		}
	}
	assert(false);
}

void createClass(ORange,IRange)(ref ORange o, IRange i, string gladeString) {
	o.formattedWrite("\tstring __gladeString = `%s`;\n", gladeString);
	o.put("\tBuilder __superSecretBuilder;\n");
	foreach(it; i) {
		if(it.kind == XmlTokenKind.Open && it.name == "object") {
			o.formattedWrite("\t%s %s;\n", it["class"][3 .. $], it["id"]);
		}
	}
	o.put("\n");
}

void createObjects(ORange,IRange)(ref ORange o, IRange i) {
	o.formattedWrite("\tthis() {\n");
	o.put("\t\t__superSecretBuilder = new Builder();\n");
	o.put("\t\t__superScretBuilder.addFromString(__gladeString);\n");
	string box;
	int second = 0;
	foreach(it; i) {
		if(it.kind == XmlTokenKind.Open && it.name == "object") {
			++second;
			if(second == 2) {
				box = it.name;
			}
			assert(it.has("id"));
			assert(it.has("class"));
			o.formattedWrite("\t\tthis.%s = cast(%s)__superScretBuilder." ~
				"getObject(%s);\n", it["id"], it["class"][3 .. $], it["id"], 
			);
		}
	}
	o.formattedWrite("\t\tthis.add(%s);\n", box);

	connectHandler(o, i);
	o.formattedWrite("\t}\n");
}

bool hasToggle(string s) {
	return s == "GtkToggleButton" || s == "GtkCheckButton" || s == "GtkMenuButton";
}

void connectHandler(ORange, IRange)(ref ORange o, IRange i) {
	foreach(it; i) {
		if(it.kind == XmlTokenKind.Open && it.name == "object") {
			if(it.has("class") && it["class"] == "GtkButton") {
				o.formattedWrite("\t\tthis.%s.addOnClick(&this.%sDele);\n",
					it["id"], it["id"]
				);
			} else if(it.has("class") && hasToggle(it["class"])) {
				o.formattedWrite("\t\tthis.%s.addOnToggle(&this.%sDele);\n",
					it["id"], it["id"]
				);
			}
		}
	}
}

void createOnClickHandler(ORange, IRange)(ref ORange o, IRange i) {
	foreach(it; i) {
		if(it.kind == XmlTokenKind.Open && it.name == "object") {
			if(it.has("class") && 
					(it["class"] == "GtkButton" || hasToggle(it["class"]))) {
				o.formattedWrite(
					"\n\tvoid %sDele(%s sig) {\n\t\t%sHandler(sig);\n\t}\n",
					it["id"], it["class"][3 .. $], it["id"]
				);

				o.formattedWrite(
					"\n\tvoid %sHandler(%s sig) {\n\t\t" ~ 
					"writeln(\"%sHandlerStub\");\n\t}\n",
					it["id"], it["class"][3 .. $], it["id"], it["id"]
				);
			}
		}
	}
}

void main() {
	LogManager.globalLogLevel = LogLevel.trace;
	string input = cast(string)read("test1.glade");
	auto tokenRange = input.xmlTokenRange();
	auto payLoad = tokenRange.dropUntil!(a => a.kind == XmlTokenKind.Open && 
		a.name == "object" && a.has("class") && 
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
		assert(it.has("id"));
		assert(it.has("class"));
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
	createClass(ofr, payLoad, input);
	createObjects(ofr, payLoad);
	createOnClickHandler(ofr, payLoad);
	ofr.formattedWrite("}\n");
}

module utga;

import std.stdio;
import std.algorithm;
import std.exception;
import core.stdc.string;


struct TGAHeader {
align (1):
	ubyte	idlength;
	ubyte 	colormaptype;
	ubyte 	datatypecode;
	ushort 	colormaporigin;
	ushort 	colormaplength;
	ubyte 	colormapdepth;
	ushort 	x_origin;
	ushort 	y_origin;
	ushort 	width;
	ushort 	height;
	ubyte 	bitsperpixel;
	ubyte 	imagedescriptor;
}

struct TGAColor {
	ubyte[4] bgra;
	ubyte bytespp = 1;

	this(ubyte R, ubyte G, ubyte B, ubyte A=255)
	{
		bytespp = 4;
		bgra[0] = B;
		bgra[1] = G;
		bgra[2] = R;
		bgra[3] = A;
	}

	this(ubyte v)
	{
		bgra[0] = v;
	}

	this(ubyte[] p)
	{
		bytespp = cast(ubyte)p.length;
		for (int i=0; i<cast(int)p.length; i++) {
			bgra[i] = p[i];
		}
	}

	ubyte opIndex(int i)
	{
		return bgra[i];
	}

	TGAColor opBinary(string op)(float intensity) if (op == "*")
	{
		TGAColor res = this;
		intensity = ( intensity > 1f ? 1f : (intensity < 0f ? 0f : intensity));
		for (int i=0; i<4; i++) res.bgra[i] = cast(ubyte)(bgra[i] * intensity);
		return res;
	}
}

class TGAImage {
protected:
	ubyte[] _data;
	ushort _width;
	ushort _height;
	ubyte _bytespp;

	bool load_rle_data(File input)
	{
		ulong pixelcount = _width*_height;
		ulong currentpixel = 0;
		ulong currentbyte = 0;
		TGAColor colorbuffer;
		do {
			ubyte chunkheader = 0;
			input.rawRead((&chunkheader)[0..1]);
			if (chunkheader<128) {
				chunkheader++;
				for (int i=0; i<chunkheader; i++) {
					input.rawRead(colorbuffer.bgra[0.._bytespp]);
					for (int t=0; t<_bytespp; t++)
						_data[currentbyte++] = colorbuffer.bgra[t];
					currentpixel++;
					if (currentpixel>pixelcount)
						return false;
				}
			}
			else {
				chunkheader -= 127;
				input.rawRead(colorbuffer.bgra[0.._bytespp]);
				for (int i=0; i<chunkheader; i++) {
					for (int t=0; t<_bytespp; t++)
						_data[currentbyte++] = colorbuffer.bgra[t];
					currentpixel++;
					if (currentpixel>pixelcount)
						return false;
				}
			}
		} while (currentpixel < pixelcount);
		return true;
	}

	bool unload_rle_data(File output)
	{
		enum ubyte max_chunk_length = 128;
		ulong npixels = _width*_height;
		ulong curpix = 0;
		while (curpix<npixels) {
			ulong chunkstart = curpix*_bytespp;
			ulong curbyte = curpix*_bytespp;
			ubyte run_length = 1;
			bool raw = true;
			while (curpix+run_length<npixels && run_length<max_chunk_length) {
				bool succ_eq = true;
				for (int t=0; succ_eq && t<_bytespp; t++)
					succ_eq = (_data[curbyte+t]==_data[curbyte+t+_bytespp]);
				curbyte +=_bytespp;
				if (1==run_length) {
					raw = !succ_eq;
				}
				if (raw && succ_eq) {
					run_length--;
					break;
				}
				if (!raw && !succ_eq) {
					break;
				}
				run_length++;
			}
			curpix += run_length;
			auto tmp = cast(ubyte)(raw?run_length-1:run_length+127);
			output.rawWrite((&tmp)[0..1]);
			output.rawWrite(_data[chunkstart..(chunkstart+(raw?run_length*_bytespp:_bytespp))]);
		}
		return true;
	}

public:
	enum Format {
		GRAYSCALE=1,
		RGB=3,
		RGBA=4
	}

	this() {}

	this(ushort w, ushort h, ubyte bpp)
	{
		_width = w;
		_height = h;
		_bytespp = bpp;
		_data.length = _width*_height*_bytespp;
	}

	this(const TGAImage img)
	{
		_width = img._width;
		_height = img._height;
		_bytespp = img._bytespp;
		_data = img._data.dup;
	}

	bool read_tga_file(const string filename)
	{
		if (_data) _data = [];
		auto input = File(filename, "rb");
		TGAHeader header;
		input.rawRead((&header)[0..1]);
		_width = header.width;
		_height = header.height;
		_bytespp = header.bitsperpixel >> 3;
		enforce(0<_width && 0<_height && (Format.GRAYSCALE==_bytespp || Format.RGB==_bytespp || Format.RGBA==_bytespp));
		_data.length = _bytespp*_width*_height;
		if (3==header.datatypecode || 2==header.datatypecode) {
			input.rawRead(_data);
		}
		else if (10==header.datatypecode || 11==header.datatypecode) {
			if (!load_rle_data(input)) {
				input.close;
				return false;
			}
		}
		else {
			input.close;
			return false;
		}
		if (!(header.imagedescriptor & 0x20)) {
			flip_vertically();
		}
		if (header.imagedescriptor & 0x10) {
			flip_horizontally();
		}
		input.close;
		return true;
	}

	bool write_tga_file(const string filename, bool rle=true)
	{
		ubyte[4] developer_area_ref = [0, 0, 0, 0];
		ubyte[4] extension_area_ref = [0, 0, 0, 0];
		ubyte[18] footer = ['T','R','U','E','V','I','S','I','O','N','-','X','F','I','L','E','.','\0'];
		auto output = File(filename, "wb");
		TGAHeader header;
		header.bitsperpixel = cast(ubyte)(_bytespp<<3);
		header.width = _width;
		header.height = _height;
		header.datatypecode = (_bytespp==Format.GRAYSCALE?(rle?11:3):(rle?10:2));
		header.imagedescriptor = 0x20;
		output.rawWrite((&header)[0..1]);
		if (!rle) {
			output.rawWrite(_data);
		}
		else {
			if (!unload_rle_data(output))
				return false;
		}
		output.rawWrite(developer_area_ref);
		output.rawWrite(extension_area_ref);
		output.rawWrite(footer);
		output.close;
		return true;
	}

	bool flip_horizontally()
	{
		if (!_data) return false;
		int half = _width >> 1;
		for (int i=0; i<half; i++) {
			for (int j=0; j<_height; j++) {
				TGAColor c1 = get(i, j);
				TGAColor c2 = get(_width-1-i, j);
				set(i, j, c2);
				set(_width-1-i, j, c1);
			}
		}
		return true;
	}

	bool flip_vertically()
	{
		if (!_data) return false;
		ulong bytes_per_line = _width*_bytespp;
		ubyte[] line; line.length = bytes_per_line;
		int half = _height >> 1;
		for (int j=0; j<half; j++) {
			ulong l1 = j*bytes_per_line;
			ulong l2 = (_height-1-j)*bytes_per_line;
			swapRanges(_data[l1..l1+bytes_per_line], _data[l2..l2+bytes_per_line]);
		}
		return true;
	}

	bool scale(ushort w, ushort h)
	{
		if (w<=0 || h<=0 || !_data) return false;
		ubyte[] tdata; tdata.length = w*h*_bytespp;
		int nscanline = 0;
		int oscanline = 0;
		int erry = 0;
		ulong nlinebytes = w*_bytespp;
		ulong olinebytes = _width*_bytespp;
		for (int j=0; j<_height; j++) {
			int errx = _width-w;
			int nx = -cast(int)_bytespp;
			int ox = -cast(int)_bytespp;
			for (int i=0; i<_width; i++) {
				ox += _bytespp;
				errx += w;
				while (errx>=cast(int)_width) {
					errx -= _width;
					nx += _bytespp;
					tdata[nscanline+nx..nscanline+nx+_bytespp] = _data[oscanline+ox.._bytespp+oscanline+ox];
				}
			}
			erry += h;
			oscanline += olinebytes;
			while (erry>=cast(int)_height) {
				if (erry>=cast(int)_height<<1)
					tdata[nscanline+nlinebytes..nlinebytes+nscanline+nlinebytes] = tdata[nscanline..nscanline+nlinebytes];
				erry -= _height;
				nscanline += nlinebytes;
			}
		}
		_data = [];
		_data = tdata;
		_width = w;
		_height = h;
		return true;
	}

	TGAColor get(int x, int y)
	{
		if (!_data || x<0 || y<0 || x>=_width || y>=_height)
			return TGAColor();
		return TGAColor(_data[(x+y*_width)*_bytespp..(x+y*_width)*_bytespp+_bytespp]);
	}

	bool set(int x, int y, TGAColor c)
	{
		if (!_data || x<0 || y<0 || x>=_width || y>=_height)
			return false;
		memcpy(_data.ptr+(x+y*_width)*_bytespp, c.bgra.ptr, _bytespp);
		return true;
	}

	bool set(int x, int y, const TGAColor c)
	{
		if (!_data || x<0 || y<0 || x>=_width || y>=_height)
			return false;
		memcpy(_data.ptr+(x+y*_width)*_bytespp, c.bgra.ptr, _bytespp);
		return true;
	}

	TGAImage opAssing(const TGAImage img)
	{
		if (this != img) {
			if (_data) _data = [];
			_width = img._width;
			_height = img._height;
			_bytespp = img._bytespp;
			_data = img._data.dup;
		}
		return this;
	}

	@property
	auto width()
	{
		return _width;
	}

	@property
	auto height()
	{
		return _height;
	}

	@property
	auto bytespp() {
		return _bytespp;
	}

	@property
	auto data() {
		return _data;
	}

	@property
	void clear() {
		_data = [];
		_data.length = _width*_height*_bytespp;
	}
}

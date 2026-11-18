// Generate video frames independently of canvas display updates on the build Mac.
self.onmessage = async ({data: {width, height, format}}) => {
    try {
        const generator = new VideoTrackGenerator();
        const writer = generator.writable.getWriter();
        const track = generator.track;
        self.postMessage({track}, [track]);
        const area = width * height;
        const pixels = new Uint8Array(format === "NV12" ? area * 3 / 2 : area * 4);
        for (let number = 1; ; number++) {
            if (format === "NV12") {
                pixels.fill(number % 2 ? 82 : 41, 0, area);
                for (let i = area; i < pixels.length; i += 2) {
                    pixels[i] = number % 2 ? 90 : 240;
                    pixels[i + 1] = number % 2 ? 240 : 110;
                }
            } else {
                for (let i = 0; i < pixels.length; i += 4) {
                    pixels[i] = number % 2 ? 224 : 32;
                    pixels[i + 1] = 48;
                    pixels[i + 2] = number % 2 ? 32 : 224;
                    pixels[i + 3] = 255;
                }
            }
            const frame = new VideoFrame(pixels, {format, codedWidth: width,
                codedHeight: height, timestamp: number * 100000, duration: 100000});
            try { await writer.write(frame); } finally { frame.close(); }
            self.postMessage({number});
            await new Promise(resolve => setTimeout(resolve, 100));
        }
    } catch (error) {
        self.postMessage({error: String(error)});
    }
};

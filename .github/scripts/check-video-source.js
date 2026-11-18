// Generate video frames independently of canvas display updates on the build Mac.
self.onmessage = async ({data: {width, height}}) => {
    try {
        const generator = new VideoTrackGenerator();
        const writer = generator.writable.getWriter();
        const track = generator.track;
        self.postMessage({track}, [track]);
        const pixels = new Uint8Array(width * height * 4);
        for (let number = 1; ; number++) {
            for (let i = 0; i < pixels.length; i += 4) {
                pixels[i] = number % 2 ? 224 : 32;
                pixels[i + 1] = 48;
                pixels[i + 2] = number % 2 ? 32 : 224;
                pixels[i + 3] = 255;
            }
            const frame = new VideoFrame(pixels, {format: "RGBA", codedWidth: width,
                codedHeight: height, timestamp: number * 100000, duration: 100000});
            try { await writer.write(frame); } finally { frame.close(); }
            self.postMessage({number});
            await new Promise(resolve => setTimeout(resolve, 100));
        }
    } catch (error) {
        self.postMessage({error: String(error)});
    }
};

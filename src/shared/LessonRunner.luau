--!strict
-- Runs a tutorial lesson step by step (DEVELOPMENT.md §28, TUT-01). Pure: a lesson is a list of steps,
-- each with a prompt and a condition checked every frame against a context the caller provides.

export type Step = {
	text: string, -- what to tell the player
	hint: string?, -- smaller line, e.g. the key to press
	check: (ctx: any, memory: { [string]: any }) -> boolean, -- true when the step is done
	enter: ((ctx: any, memory: { [string]: any }) -> ())?, -- called once when the step starts
}

export type Lesson = { id: string, title: string, steps: { Step } }

local LessonRunner = {}
LessonRunner.__index = LessonRunner

export type Runner = typeof(setmetatable(
	{} :: { lesson: Lesson, index: number, memory: { [string]: any }, entered: boolean, done: boolean },
	LessonRunner
))

function LessonRunner.new(lesson: Lesson): Runner
	return setmetatable({ lesson = lesson, index = 1, memory = {}, entered = false, done = false }, LessonRunner)
end

function LessonRunner.current(self: Runner): Step?
	return self.lesson.steps[self.index]
end

-- Advances at most one step per call. Returns true when the lesson has just finished.
function LessonRunner.update(self: Runner, ctx: any): boolean
	if self.done then
		return false
	end
	local step = self:current()
	if not step then
		self.done = true
		return true
	end
	if not self.entered then
		self.entered = true
		if step.enter then
			step.enter(ctx, self.memory)
		end
	end
	if step.check(ctx, self.memory) then
		self.index += 1
		self.entered = false
		if self.index > #self.lesson.steps then
			self.done = true
			return true
		end
	end
	return false
end

function LessonRunner.progress(self: Runner): (number, number)
	return math.min(self.index, #self.lesson.steps), #self.lesson.steps
end

return LessonRunner
